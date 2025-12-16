#!/bin/bash
# ========================================
# SCRIPT 4: Deploy ArgoCD & Applications
# ========================================
# Run from DEV SERVER after running script 3
# This script deploys ArgoCD and all KubeStock applications
# using the demo branch of kubestock-gitops
#
# Architecture:
# - ArgoCD is installed manually (one-time setup)
# - External Secrets Operator is deployed via ArgoCD/Helm
# - All other apps are deployed via ArgoCD
#
# Prerequisites:
# - Script 3 completed (Kubernetes cluster ready)
# - IAM user 'kubestock-demo-external-secrets' with policy:
#   - SecretsManager: kubestock-demo/* (read)
#   - ECR: GetAuthorizationToken (all resources)
#   - ECR: BatchGetImage, GetDownloadUrlForLayer, BatchCheckLayerAvailability
#         on repository/kubestock/* (NOT kubestock-demo/* - images use kubestock/ prefix)

set -euo pipefail

# Configuration
ARGOCD_VERSION="v2.9.3"
ARGOCD_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
GITOPS_DIR="$HOME/kubestock-core/gitops"
AWS_REGION="ap-south-1"

# ESO IAM User for demo
ESO_IAM_USER="kubestock-demo-external-secrets"

echo "=========================================="
echo "Demo Script 4: Deploy ArgoCD & Applications"
echo "=========================================="
echo "ArgoCD Version: $ARGOCD_VERSION"
echo "GitOps Branch: demo"
echo ""

# Ensure we're using the demo branch in gitops
echo "📋 Step 0/9: Ensuring gitops is on demo branch..."
cd "$GITOPS_DIR"
git fetch origin
git checkout demo
git pull origin demo
echo "   ✅ Using gitops demo branch"
echo ""

# Step 1: Verify Prerequisites
echo "🔧 Step 1/9: Verifying prerequisites..."
kubectl cluster-info >/dev/null 2>&1 || { echo "❌ kubectl not configured"; exit 1; }
aws sts get-caller-identity >/dev/null 2>&1 || { echo "❌ AWS CLI not configured"; exit 1; }
helm version >/dev/null 2>&1 || { 
    echo "   Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}
echo "   ✅ Prerequisites verified"
echo ""

# Step 2: Install ArgoCD
echo "🚀 Step 2/9: Installing ArgoCD ${ARGOCD_VERSION}..."
if kubectl get namespace argocd &> /dev/null; then
    echo "   ArgoCD namespace already exists"
else
    kubectl create namespace argocd
    echo "   Created argocd namespace"
fi

if kubectl get deployment argocd-server -n argocd &> /dev/null; then
    echo "   ArgoCD already installed, skipping..."
else
    echo "   Applying ArgoCD manifest..."
    kubectl apply -n argocd -f ${ARGOCD_MANIFEST}
    echo "   Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
fi

# Expose ArgoCD as NodePort
if kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}' | grep -q "NodePort"; then
    echo "   ArgoCD already exposed as NodePort"
else
    echo "   Exposing ArgoCD on NodePort 32001..."
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"name":"http","port": 80, "nodePort": 32001, "targetPort": 8080}, {"name":"https","port": 443, "nodePort": 30443, "targetPort": 8080}]}}'
fi

# Get ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")
echo "   ✅ ArgoCD installed"
echo ""

# Step 3: Apply ArgoCD Projects
echo "📁 Step 3/9: Creating ArgoCD projects..."
for project_file in "$GITOPS_DIR/argocd/projects/"*.yaml; do
    if [ -f "$project_file" ]; then
        kubectl apply -f "$project_file"
        echo "   Applied $(basename $project_file)"
    fi
done
echo "   ✅ ArgoCD projects created"
echo ""

# Step 4: Deploy External Secrets Operator via ArgoCD
echo "📦 Step 4/9: Deploying External Secrets Operator via ArgoCD..."

# Deploy ESO operator app (uses Helm chart)
kubectl apply -f "$GITOPS_DIR/apps/external-secrets-operator.yaml"
echo "   Applied external-secrets-operator.yaml"

# Deploy ESO prerequisites (creates namespace)
kubectl apply -f "$GITOPS_DIR/apps/external-secrets-prereqs.yaml"
echo "   Applied external-secrets-prereqs.yaml"

echo "   Waiting for External Secrets Operator to be deployed..."
sleep 30

# Wait for ESO deployment to be available
echo "   Checking if ESO is ready..."
for i in {1..20}; do
    if kubectl get deployment external-secrets -n external-secrets &> /dev/null; then
        kubectl wait --for=condition=available --timeout=60s deployment/external-secrets -n external-secrets 2>/dev/null && break
    fi
    echo "   Waiting for ESO deployment... ($i/20)"
    sleep 10
done
echo "   ✅ External Secrets Operator deployed via ArgoCD"
echo ""

# Step 5: Create AWS credentials secret for External Secrets
echo "🔑 Step 5/9: Creating AWS credentials for External Secrets..."

# Ensure namespace exists
kubectl create namespace external-secrets 2>/dev/null || true

# Check if secret already exists
if kubectl get secret aws-external-secrets-creds -n external-secrets &> /dev/null; then
    echo "   AWS credentials secret already exists, skipping..."
else
    # Get existing access keys (sorted by creation date, oldest first)
    EXISTING_KEYS=$(aws iam list-access-keys --user-name ${ESO_IAM_USER} \
        --query 'AccessKeyMetadata | sort_by(@, &CreateDate)[*].AccessKeyId' --output text 2>/dev/null || echo "")
    KEY_COUNT=$(echo "$EXISTING_KEYS" | wc -w)
    
    echo "   Found $KEY_COUNT existing access key(s) for ${ESO_IAM_USER}"
    
    # AWS allows max 2 keys per user - delete oldest if at limit
    if [ "$KEY_COUNT" -ge 2 ]; then
        OLDEST_KEY=$(echo "$EXISTING_KEYS" | awk '{print $1}')
        echo "   Deleting oldest access key: $OLDEST_KEY (AWS allows max 2 keys)"
        aws iam delete-access-key --user-name ${ESO_IAM_USER} --access-key-id "$OLDEST_KEY"
    fi
    
    # Create new access key
    echo "   Creating new access key for ${ESO_IAM_USER}..."
    ACCESS_KEY_JSON=$(aws iam create-access-key --user-name ${ESO_IAM_USER})
    AWS_ACCESS_KEY_ID=$(echo $ACCESS_KEY_JSON | jq -r '.AccessKey.AccessKeyId')
    AWS_SECRET_ACCESS_KEY=$(echo $ACCESS_KEY_JSON | jq -r '.AccessKey.SecretAccessKey')
    echo "   Created access key: $AWS_ACCESS_KEY_ID"
    
    kubectl create secret generic aws-external-secrets-creds \
        --from-literal=access-key-id="$AWS_ACCESS_KEY_ID" \
        --from-literal=secret-access-key="$AWS_SECRET_ACCESS_KEY" \
        --namespace=external-secrets
fi
echo "   ✅ AWS credentials secret created"
echo ""

# Step 6: Deploy External Secrets Config
echo "🔐 Step 6/9: Deploying External Secrets configuration..."

# Deploy external-secrets config (ClusterSecretStore, ECR configs)
kubectl apply -f "$GITOPS_DIR/apps/external-secrets.yaml"
echo "   Applied external-secrets.yaml (ClusterSecretStore, ECR configs)"

# Deploy shared RBAC
kubectl apply -f "$GITOPS_DIR/apps/shared-rbac.yaml"
echo "   Applied shared-rbac.yaml"

echo "   Waiting for External Secrets config to sync..."
sleep 15

# Wait for ECR secret to be generated
echo "   Waiting for ECR credentials to be generated..."
for i in {1..24}; do
    if kubectl get secret ecr-cred-source -n external-secrets &> /dev/null; then
        echo "   ECR source secret ready"
        break
    fi
    echo "   Waiting for ECR source secret... ($i/24)"
    sleep 10
done

# Restart ESO to ensure PushSecrets reconcile properly after source secret exists
echo "   Restarting External Secrets to ensure PushSecrets sync..."
kubectl rollout restart deployment external-secrets -n external-secrets
kubectl rollout status deployment external-secrets -n external-secrets --timeout=120s

# Wait for PushSecrets to create ecr-cred in target namespaces
echo "   Waiting for ECR credentials to be pushed to application namespaces..."
kubectl create namespace kubestock-production 2>/dev/null || true
kubectl create namespace kubestock-staging 2>/dev/null || true
for i in {1..12}; do
    if kubectl get secret ecr-cred -n kubestock-production &> /dev/null && \
       kubectl get secret ecr-cred -n kubestock-staging &> /dev/null; then
        echo "   ECR credentials pushed to all namespaces"
        break
    fi
    echo "   Waiting for ECR secrets in application namespaces... ($i/12)"
    sleep 10
done

echo "   ✅ External Secrets configuration deployed"
echo ""

# Step 7: Deploy Infrastructure Apps
echo "🏗️  Step 7/9: Deploying infrastructure apps..."

# Apply metrics server and EBS CSI driver
kubectl apply -f "$GITOPS_DIR/apps/metrics-server.yaml"
echo "   Applied metrics-server.yaml"
kubectl apply -f "$GITOPS_DIR/apps/ebs-csi-driver.yaml"
echo "   Applied ebs-csi-driver.yaml"
kubectl apply -f "$GITOPS_DIR/apps/reloader.yaml"
echo "   Applied reloader.yaml"

echo "   ✅ Infrastructure apps deployed"
echo ""

# Step 8: Deploy Remaining Apps
echo "🌐 Step 8/9: Deploying remaining apps..."

# Apply all other apps (skip already applied ones)
SKIP_APPS="external-secrets-operator.yaml external-secrets-prereqs.yaml external-secrets.yaml shared-rbac.yaml metrics-server.yaml ebs-csi-driver.yaml reloader.yaml"

for app_file in "$GITOPS_DIR/apps/"*.yaml; do
    if [ -f "$app_file" ]; then
        app_name=$(basename "$app_file")
        # Skip already applied apps
        if [[ "$SKIP_APPS" == *"$app_name"* ]]; then
            continue
        fi
        kubectl apply -f "$app_file" 2>/dev/null || true
        echo "   Applied $app_name"
    fi
done

# Apply production apps
if [ -d "$GITOPS_DIR/apps/production" ]; then
    echo ""
    echo "   Deploying production applications..."
    for app_file in "$GITOPS_DIR/apps/production/"*.yaml; do
        if [ -f "$app_file" ]; then
            kubectl apply -f "$app_file"
            echo "   Applied production/$(basename $app_file)"
        fi
    done
fi

# Apply staging apps
if [ -d "$GITOPS_DIR/apps/staging" ]; then
    echo ""
    echo "   Deploying staging applications..."
    for app_file in "$GITOPS_DIR/apps/staging/"*.yaml; do
        if [ -f "$app_file" ]; then
            kubectl apply -f "$app_file"
            echo "   Applied staging/$(basename $app_file)"
        fi
    done
fi
echo "   ✅ All applications deployed"
echo ""

# Step 9: Verification
echo "✅ Step 9/9: Verifying deployment..."
echo ""
echo "   Waiting 30 seconds for applications to sync..."
sleep 30

echo ""
echo "   ArgoCD Applications:"
kubectl get applications -n argocd
echo ""

echo "   ClusterSecretStore:"
kubectl get clustersecretstore 2>/dev/null || echo "   (Waiting for sync...)"
echo ""

echo "   External Secrets (all namespaces):"
kubectl get externalsecrets -A 2>/dev/null || echo "   (Waiting for sync...)"
echo ""

# Get node IPs for access URLs
MASTER_IP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "10.100.10.21")

echo "=========================================="
echo "✅ Demo Script 4 Complete!"
echo "=========================================="
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                         ArgoCD Access Information                            ║"
echo "╠══════════════════════════════════════════════════════════════════════════════╣"
echo "║ URL:      http://${MASTER_IP}:32001                                         ║"
echo "║ Username: admin                                                              ║"
if [ -n "$ARGOCD_PASSWORD" ]; then
echo "║ Password: ${ARGOCD_PASSWORD}                                                ║"
fi
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Demo environment uses the 'demo' branch of kubestock-gitops which:"
echo "  - Has NO cluster-autoscaler (demo uses static nodes)"
echo "  - Uses kubestock-demo/* secrets in AWS Secrets Manager"
echo "  - All ArgoCD apps target the 'demo' branch"
echo ""
echo "To access ArgoCD from your local machine, set up SSH tunnel:"
echo "  ssh -L 8080:${MASTER_IP}:32001 ubuntu@<dev-server-ip>"
echo "  Then open: http://localhost:8080"
echo ""
echo "To check sync status:"
echo "  kubectl get applications -n argocd"
echo ""
