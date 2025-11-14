# Kubectl-Only Developer Setup (Cluster Admin Guide)

This guide is for the **cluster administrator** to provision a kubectl-only developer. These developers:
- Tunnel through the bastion to the NLB
- Do NOT SSH into control plane or worker nodes
- Receive a minimally scoped kubeconfig (token-based, not admin certs)

## Overview

Provisioning flow:
1. Pick access scope (namespace-only or broader) and a target namespace
2. Create a namespace (if not existing)
3. Create a service account for the developer
4. Bind RBAC roles (least privilege)
5. Retrieve a token
6. Generate a kubeconfig referencing the NLB endpoint
7. Distribute securely; set file permissions
8. (Optional) Rotate / revoke later

## Quick recipe: cluster-admin (GitOps operator)

If you need a kubectl-only developer who can do everything in every namespace (e.g., to operate ArgoCD, install CRDs, cluster-scoped controllers), run this on the dev server:

```bash
cd ~/kubestock-infrastructure
./scripts/gen-kubectl-dev-kubeconfig.sh gitops ops-gitops cluster-admin
# Output: kubeconfig-dev-gitops (token-based, cluster-admin)
```

Share the file securely. The developer follows `developer-access.md` to set up the bastion tunnel, then:

```bash
mkdir -p ~/.kube
cp kubeconfig-dev-gitops ~/.kube/kubestock-config
chmod 600 ~/.kube/kubestock-config
export KUBECONFIG=~/.kube/kubestock-config
kubectl get nodes
kubectl get pods -A
```

To revoke later:

```bash
kubectl delete clusterrolebinding dev-gitops-cluster-admin 2>/dev/null || true
kubectl -n ops-gitops delete sa dev-gitops
```

---

## 1. Choose access scope

Recommended scopes:
- Read-only (cluster-wide): built-in `view` ClusterRole or `cluster-reader` if available
- Namespace admin: combine Roles for common operations in a single namespace
- Elevated (avoid unless needed): `edit` or `admin` for a namespace, never `cluster-admin` for general use

Role-to-scope mapping (examples):

| Team Role | Typical Scope | Notes |
| --- | --- | --- |
| GitOps & Deployment (ArgoCD/operator, CRDs) | cluster-admin | Full cluster lifecycle actions; narrow later with tailored ClusterRoles if desired |
| Security & Service Mesh (Trivy, Istio) | cluster-admin initially | Needs CRDs/webhooks/cluster-scoped config; tighten after bootstrap |
| Observability (Prometheus, Loki, Grafana) | cluster-admin initially | Installs CRDs/operators and cluster-wide scraping; can narrow once stabilized |

## 2. Variables (export once per user)
```bash
DEV_USERNAME="alice"          # lowercase identifier
DEV_NAMESPACE="dev-alice"     # namespace for user sandbox
SCOPE="namespace-admin"       # one of: readonly|namespace-admin|cluster-read|cluster-admin (last discouraged)
WORKDIR="$(pwd)"              # where output kubeconfig will be placed
KUBECONFIG_ADMIN=~/kubeconfig  # admin kubeconfig location
```

## 3. Ensure namespace exists
```bash
kubectl get ns "${DEV_NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${DEV_NAMESPACE}"
```

## 4. Create service account
```bash
kubectl -n "${DEV_NAMESPACE}" create sa "dev-${DEV_USERNAME}" --dry-run=client -o yaml | kubectl apply -f -
```

## 5. RBAC bindings

Define logic based on `$SCOPE`:
```bash
case "$SCOPE" in
  readonly)
    # cluster-wide read access (non-secret objects)
    kubectl create clusterrolebinding "dev-${DEV_USERNAME}-view" \
      --clusterrole=view \
      --serviceaccount="${DEV_NAMESPACE}:dev-${DEV_USERNAME}" --dry-run=client -o yaml | kubectl apply -f -
    ;;
  cluster-read)
    kubectl create clusterrolebinding "dev-${DEV_USERNAME}-read" \
      --clusterrole=view \
      --serviceaccount="${DEV_NAMESPACE}:dev-${DEV_USERNAME}" --dry-run=client -o yaml | kubectl apply -f -
    ;;
  namespace-admin)
    # Grant edit rights only in their namespace
    kubectl -n "${DEV_NAMESPACE}" create rolebinding "dev-${DEV_USERNAME}-edit" \
      --clusterrole=edit \
      --serviceaccount="${DEV_NAMESPACE}:dev-${DEV_USERNAME}" --dry-run=client -o yaml | kubectl apply -f -
    ;;
  cluster-admin)
    echo "Warning: granting cluster-admin; reconsider least privilege." >&2
    kubectl create clusterrolebinding "dev-${DEV_USERNAME}-cluster-admin" \
      --clusterrole=cluster-admin \
      --serviceaccount="${DEV_NAMESPACE}:dev-${DEV_USERNAME}" --dry-run=client -o yaml | kubectl apply -f -
    ;;
  *) echo "Unsupported SCOPE: $SCOPE"; exit 1;;
 esac
```

## 6. Retrieve token (Kubernetes >=1.24 preferred method)
```bash
DEV_TOKEN=$(kubectl -n "${DEV_NAMESPACE}" create token "dev-${DEV_USERNAME}")
```
If `kubectl create token` isn’t available or returns empty, fall back:
```bash
SA_SECRET=$(kubectl -n "${DEV_NAMESPACE}" get sa "dev-${DEV_USERNAME}" -o jsonpath='{.secrets[0].name}')
DEV_TOKEN=$(kubectl -n "${DEV_NAMESPACE}" get secret "$SA_SECRET" -o jsonpath='{.data.token}' | base64 -d)
```

## 7. Extract cluster CA & NLB endpoint
```bash
CA_DATA=$(awk '/certificate-authority-data:/ {print $2; exit}' "$KUBECONFIG_ADMIN")
NLB_DNS=$(terraform -chdir=~/kubestock-infrastructure/terraform/prod output -raw nlb_dns_name)
```

## 8. Generate kubeconfig
```bash
OUT_FILE="${WORKDIR}/kubeconfig-dev-${DEV_USERNAME}"
cat > "$OUT_FILE" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: kubestock
  cluster:
    certificate-authority-data: ${CA_DATA}
    server: https://${NLB_DNS}:6443
users:
- name: dev-${DEV_USERNAME}
  user:
    token: ${DEV_TOKEN}
contexts:
- name: dev-${DEV_USERNAME}@kubestock
  context:
    cluster: kubestock
    user: dev-${DEV_USERNAME}
current-context: dev-${DEV_USERNAME}@kubestock
EOF
chmod 600 "$OUT_FILE"
```

## 9. Distribute to developer
- Send `kubeconfig-dev-${DEV_USERNAME}` via secure channel (never commit to git) 
- Developer saves as `~/.kube/kubestock-config` or a custom file and sets:
```bash
export KUBECONFIG=~/.kube/kubestock-config
```
- They use the bastion SSH tunnel (see `developer-access.md`).

## 10. Revocation / rotation
To revoke access:
```bash
kubectl -n "${DEV_NAMESPACE}" delete sa "dev-${DEV_USERNAME}"
kubectl delete clusterrolebinding "dev-${DEV_USERNAME}-view" 2>/dev/null || true
kubectl delete rolebinding -n "${DEV_NAMESPACE}" "dev-${DEV_USERNAME}-edit" 2>/dev/null || true
```
Rotate token (no RBAC change):
```bash
DEV_TOKEN_NEW=$(kubectl -n "${DEV_NAMESPACE}" create token "dev-${DEV_USERNAME}")
# Regenerate kubeconfig with new token (repeat step 8)
```

## 11. Validation
```bash
KUBECONFIG=kubeconfig-dev-${DEV_USERNAME} kubectl auth can-i list pods -n "${DEV_NAMESPACE}" --as=system:serviceaccount:"${DEV_NAMESPACE}":dev-${DEV_USERNAME}
KUBECONFIG=kubeconfig-dev-${DEV_USERNAME} kubectl get nodes  # should work only if view binding cluster-wide
```

## 12. Scripted automation (optional)
A helper script `scripts/gen-kubectl-dev-kubeconfig.sh` (see repository) wraps these steps.

Examples:

```bash
# Namespace-level admin for an app owner
./scripts/gen-kubectl-dev-kubeconfig.sh appowner dev-app namespace-admin

# Read-only cluster-wide observer
./scripts/gen-kubectl-dev-kubeconfig.sh observer ops-observer readonly

# Cluster-wide admin (GitOps operator)
./scripts/gen-kubectl-dev-kubeconfig.sh gitops ops-gitops cluster-admin
```

## 13. Quick cleanup checklist
| Action | Command |
|--------|---------|
| Revoke user | delete SA + bindings |
| Rotate token | `kubectl create token` again |
| List bindings | `kubectl get clusterrolebindings | grep dev-` |
| List namespace roles | `kubectl -n $DEV_NAMESPACE get rolebindings` |

## 14. Security considerations
- Prefer namespace-scoped permissions; grant cluster-wide only when required.
- Tokens retrieved via `kubectl create token` may be time-bound; enforce periodic rotation.
- Maintain an inventory of issued kubeconfigs and owners.
- Audit with:
```bash
kubectl get clusterrolebindings | grep dev-
kubectl -n ${DEV_NAMESPACE} get rolebindings | grep dev-
```
- Consider OIDC integration for scalable identity (future enhancement).

---
**Next:** After generating the kubeconfig, share the `developer-access.md` instructions with the new developer.
