#!/bin/bash
# ========================================
# SCRIPT 4: Deploy ArgoCD & Applications
# ========================================
# Run from DEV SERVER after running script 3
# This script deploys ArgoCD, External Secrets Operator, and all KubeStock applications
# using the demo branch of kubestock-gitops

set -euo pipefail

# Configuration
ARGOCD_VERSION="v2.9.3"
ARGOCD_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
EXTERNAL_SECRETS_VERSION="0.9.19"
GITOPS_DIR="$HOME/kubestock-core/gitops"
AWS_REGION="ap-south-1"

# ESO IAM User for demo
ESO_IAM_USER="kubestock-demo-external-secrets"

echo "=========================================="
echo "Demo Script 4: Deploy ArgoCD & Applications"
echo "=========================================="
echo "ArgoCD Version: $ARGOCD_VERSION"
echo "External Secrets Version: $EXTERNAL_SECRETS_VERSION"
echo "GitOps Branch: demo"
echo ""

# Ensure we're using the demo branch in gitops
echo "📋 Step 0/8: Ensuring gitops is on demo branch..."
cd "$GITOPS_DIR"
git fetch origin
git checkout demo
git pull origin demo
echo "   ✅ Using gitops demo branch"
echo ""

# Step 1: Verify Prerequisites
echo "🔧 Step 1/8: Verifying prerequisites..."
kubectl cluster-info >/dev/null 2>&1 || { echo "❌ kubectl not configured"; exit 1; }
aws sts get-caller-identity >/dev/null 2>&1 || { echo "❌ AWS CLI not configured"; exit 1; }
helm version >/dev/null 2>&1 || { 
    echo "   Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}
echo "   ✅ Prerequisites verified"
echo ""

# Step 2: Install ArgoCD
echo "🚀 Step 2/8: Installing ArgoCD ${ARGOCD_VERSION}..."
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

# Step 3: Install External Secrets Operator
echo "📦 Step 3/8: Installing External Secrets Operator ${EXTERNAL_SECRETS_VERSION}..."
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update

if kubectl get namespace external-secrets &> /dev/null; then
    echo "   external-secrets namespace already exists"
else
    kubectl create namespace external-secrets
fi

if helm list -n external-secrets | grep -q "external-secrets"; then
    echo "   External Secrets Operator already installed"
else
    echo "   Installing External Secrets Operator via Helm..."
    helm install external-secrets external-secrets/external-secrets \
        --namespace external-secrets \
        --version ${EXTERNAL_SECRETS_VERSION} \
        --wait
fi
echo "   ✅ External Secrets Operator installed"
echo ""

# Step 4: Create AWS credentials secret for External Secrets
echo "🔑 Step 4/8: Creating AWS credentials for External Secrets..."

# Check if secret already exists
if kubectl get secret aws-external-secrets-creds -n external-secrets &> /dev/null; then
    echo "   AWS credentials secret already exists, skipping..."
else
    # Check if IAM user has access keys
    EXISTING_KEYS=$(aws iam list-access-keys --user-name ${ESO_IAM_USER} --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || echo "")
    
    if [ -z "$EXISTING_KEYS" ]; then
        echo "   Creating new access key for ${ESO_IAM_USER}..."
        ACCESS_KEY_JSON=$(aws iam create-access-key --user-name ${ESO_IAM_USER})
        AWS_ACCESS_KEY_ID=$(echo $ACCESS_KEY_JSON | jq -r '.AccessKey.AccessKeyId')
        AWS_SECRET_ACCESS_KEY=$(echo $ACCESS_KEY_JSON | jq -r '.AccessKey.SecretAccessKey')
    else
        echo "   Access key exists for ${ESO_IAM_USER}: $EXISTING_KEYS"
        echo ""
        read -p "   Enter AWS_ACCESS_KEY_ID: " AWS_ACCESS_KEY_ID
        read -s -p "   Enter AWS_SECRET_ACCESS_KEY: " AWS_SECRET_ACCESS_KEY
        echo ""
    fi
    
    kubectl create secret generic aws-external-secrets-creds \
        --from-literal=access-key-id="$AWS_ACCESS_KEY_ID" \
        --from-literal=secret-access-key="$AWS_SECRET_ACCESS_KEY" \
        --namespace=external-secrets
fi
echo "   ✅ AWS credentials secret created"
echo ""

# Step 5: Apply ArgoCD Projects
echo "📁 Step 5/8: Creating ArgoCD projects..."
for project_file in "$GITOPS_DIR/argocd/projects/"*.yaml; do
    if [ -f "$project_file" ]; then
        kubectl apply -f "$project_file"
        echo "   Applied $(basename $project_file)"
    fi
done
echo "   ✅ ArgoCD projects created"
echo ""

# Step 6: Deploy Critical Infrastructure Apps
echo "🏗️  Step 6/8: Deploying critical infrastructure apps..."

# These apps need to be deployed first
kubectl apply -f "$GITOPS_DIR/apps/external-secrets.yaml"
echo "   Applied external-secrets.yaml"
kubectl apply -f "$GITOPS_DIR/apps/shared-rbac.yaml"
echo "   Applied shared-rbac.yaml"

echo "   Waiting for External Secrets config to sync..."
sleep 15

# Apply metrics server and EBS CSI driver
kubectl apply -f "$GITOPS_DIR/apps/metrics-server.yaml"
echo "   Applied metrics-server.yaml"
kubectl apply -f "$GITOPS_DIR/apps/ebs-csi-driver.yaml"
echo "   Applied ebs-csi-driver.yaml"
kubectl apply -f "$GITOPS_DIR/apps/reloader.yaml"
echo "   Applied reloader.yaml"

echo "   ✅ Critical infrastructure apps deployed"
echo ""

# Step 7: Deploy Remaining Infrastructure Apps
echo "🌐 Step 7/8: Deploying remaining infrastructure apps..."

# Apply all other apps (skip cluster-autoscaler since it's removed in demo branch)
for app_file in "$GITOPS_DIR/apps/"*.yaml; do
    if [ -f "$app_file" ]; then
        app_name=$(basename "$app_file")
        # Skip already applied apps
        case "$app_name" in
            external-secrets.yaml|shared-rbac.yaml|metrics-server.yaml|ebs-csi-driver.yaml|reloader.yaml)
                continue
                ;;
        esac
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

# Step 8: Verification
echo "✅ Step 8/8: Verifying deployment..."
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

echo "   External Secrets:"
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
