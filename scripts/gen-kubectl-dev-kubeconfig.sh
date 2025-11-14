#!/usr/bin/env bash
set -euo pipefail

# gen-kubectl-dev-kubeconfig.sh
# Generate a token-based kubeconfig for a kubectl-only developer with least-privilege RBAC.
# Usage:
#   ./scripts/gen-kubectl-dev-kubeconfig.sh <username> <namespace> <scope> [output-file]
#
# Arguments:
#   username    : short identifier (e.g. alice)
#   namespace   : target namespace (created if absent)
#   scope       : readonly|namespace-admin|cluster-read|cluster-admin
#   output-file : optional path for kubeconfig (default: ./kubeconfig-dev-<username>)
#
# Requirements:
#   - kubectl configured with admin privileges (KUBECONFIG pointing to admin kubeconfig)
#   - terraform accessible for retrieving NLB DNS (optional override via NLB_DNS env var)
#
# RBAC Mapping:
#   readonly        -> ClusterRole=view (cluster-wide read)
#   cluster-read    -> ClusterRole=view (alias, same as readonly)
#   namespace-admin -> RoleBinding to ClusterRole=edit in selected namespace
#   cluster-admin   -> ClusterRole=cluster-admin (NOT RECOMMENDED)
#
# Output:
#   Token-based kubeconfig referencing the NLB endpoint.
#
# Security Notes:
#   - Distribute output securely; chmod 600 the file.
#   - Prefer namespace-admin or readonly scopes.
#   - Rotate tokens periodically (kubectl create token).

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <username> <namespace> <scope> [output-file]" >&2
  exit 1
fi

USERNAME="$1"
NAMESPACE="$2"
SCOPE="$3"
OUT_FILE="${4:-kubeconfig-dev-${USERNAME}}"

ADMIN_KUBECONFIG="${KUBECONFIG:-$HOME/kubeconfig}"
if [[ ! -f "$ADMIN_KUBECONFIG" ]]; then
  echo "Admin kubeconfig not found: $ADMIN_KUBECONFIG" >&2
  exit 1
fi

# Acquire NLB DNS
if [[ -z "${NLB_DNS:-}" ]]; then
  if command -v terraform >/dev/null 2>&1; then
    NLB_DNS=$(terraform -chdir=~/kubestock-infrastructure/terraform/prod output -raw nlb_dns_name)
  else
    echo "terraform not found and NLB_DNS env var not set" >&2
    exit 1
  fi
fi

# Create namespace if missing
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"

SA_NAME="dev-${USERNAME}"
# Create service account (idempotent)
kubectl -n "$NAMESPACE" get sa "$SA_NAME" >/dev/null 2>&1 || \
  kubectl -n "$NAMESPACE" create sa "$SA_NAME"

# Bind RBAC based on scope
case "$SCOPE" in
  readonly|cluster-read)
    BINDING_NAME="${SA_NAME}-view"
    kubectl get clusterrolebinding "$BINDING_NAME" >/dev/null 2>&1 || \
      kubectl create clusterrolebinding "$BINDING_NAME" --clusterrole=view --serviceaccount="${NAMESPACE}:${SA_NAME}" >/dev/null
    ;;
  namespace-admin)
    BINDING_NAME="${SA_NAME}-edit"
    kubectl -n "$NAMESPACE" get rolebinding "$BINDING_NAME" >/dev/null 2>&1 || \
      kubectl -n "$NAMESPACE" create rolebinding "$BINDING_NAME" --clusterrole=edit --serviceaccount="${NAMESPACE}:${SA_NAME}" >/dev/null
    ;;
  cluster-admin)
    echo "[WARN] Granting cluster-admin to $SA_NAME (discouraged)." >&2
    BINDING_NAME="${SA_NAME}-cluster-admin"
    kubectl get clusterrolebinding "$BINDING_NAME" >/dev/null 2>&1 || \
      kubectl create clusterrolebinding "$BINDING_NAME" --clusterrole=cluster-admin --serviceaccount="${NAMESPACE}:${SA_NAME}" >/dev/null
    ;;
  *)
    echo "Unsupported scope: $SCOPE" >&2
    exit 1
    ;;
 esac

# Retrieve token (preferred method)
if DEV_TOKEN=$(kubectl -n "$NAMESPACE" create token "$SA_NAME" 2>/dev/null); then
  if [[ -z "$DEV_TOKEN" ]]; then
    echo "kubectl create token returned empty; falling back to secret extraction." >&2
  fi
fi
if [[ -z "${DEV_TOKEN:-}" ]]; then
  SA_SECRET=$(kubectl -n "$NAMESPACE" get sa "$SA_NAME" -o jsonpath='{.secrets[0].name}')
  DEV_TOKEN=$(kubectl -n "$NAMESPACE" get secret "$SA_SECRET" -o jsonpath='{.data.token}' | base64 -d)
fi

if [[ -z "$DEV_TOKEN" ]]; then
  echo "Failed to retrieve service account token" >&2
  exit 1
fi

# Extract CA data from admin kubeconfig
CA_DATA=$(awk '/certificate-authority-data:/ {print $2; exit}' "$ADMIN_KUBECONFIG")
if [[ -z "$CA_DATA" ]]; then
  echo "Could not extract certificate-authority-data from $ADMIN_KUBECONFIG" >&2
  exit 1
fi

cat > "$OUT_FILE" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: kubestock
  cluster:
    certificate-authority-data: ${CA_DATA}
    server: https://${NLB_DNS}:6443
users:
- name: ${SA_NAME}
  user:
    token: ${DEV_TOKEN}
contexts:
- name: ${SA_NAME}@kubestock
  context:
    cluster: kubestock
    user: ${SA_NAME}
current-context: ${SA_NAME}@kubestock
EOF
chmod 600 "$OUT_FILE"

cat <<MSG
Kubeconfig generated: $OUT_FILE
Distribute securely (do not commit). Example usage on developer machine:
  export KUBECONFIG=~/.kube/kubestock-config
  cp $OUT_FILE ~/.kube/kubestock-config
  chmod 600 ~/.kube/kubestock-config

Validate permissions:
  KUBECONFIG=$OUT_FILE kubectl auth can-i list pods -n $NAMESPACE
  KUBECONFIG=$OUT_FILE kubectl get pods -n $NAMESPACE

To revoke:
  kubectl delete clusterrolebinding $BINDING_NAME 2>/dev/null || true
  kubectl -n $NAMESPACE delete rolebinding $BINDING_NAME 2>/dev/null || true
  kubectl -n $NAMESPACE delete sa $SA_NAME
MSG
