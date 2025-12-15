#!/bin/bash
# ========================================
# SCRIPT 1: Terraform Apply & Setup Dev Server
# ========================================
# Run from LOCAL machine in infrastructure/terraform/demo directory
# This script: terraform apply -> SCP key -> clone repo -> ready for script 2

set -euo pipefail

SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_USER="ubuntu"

echo "=========================================="
echo "Demo Script 1: Infrastructure & Dev Server Setup"
echo "=========================================="

# Step 1: Terraform Apply
echo ""
echo "🔧 Step 1/5: Running terraform apply..."
terraform apply -auto-approve

# Step 2: Get dev server IP from terraform output
echo ""
echo "📋 Step 2/5: Getting dev server IP from terraform output..."
DEV_SERVER_IP=$(terraform output -raw dev_server_public_ip)
echo "   Dev Server IP: $DEV_SERVER_IP"

# Wait for instance to be ready
echo ""
echo "⏳ Waiting 30 seconds for instance to be fully ready..."
sleep 30

# Step 3: Copy SSH private key to dev server
echo ""
echo "🔑 Step 3/5: Copying SSH private key to dev server..."
scp -o StrictHostKeyChecking=no -o ConnectTimeout=60 -i "$SSH_KEY" "$SSH_KEY" ${SSH_USER}@${DEV_SERVER_IP}:~/.ssh/id_ed25519

# Step 4: Set correct permissions and clone repo
echo ""
echo "📦 Step 4/5: Setting up dev server (permissions + git clone)..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ${SSH_USER}@${DEV_SERVER_IP} << 'EOF'
# Set SSH key permissions
chmod 600 ~/.ssh/id_ed25519

# Clone kubestock-core if not exists
cd ~
if [ -d "kubestock-core" ]; then
    echo "Repository already exists, pulling latest..."
    cd kubestock-core && git pull && git submodule update --init --recursive
else
    echo "Cloning repository..."
    git clone --recursive https://github.com/KubeStock-DevOps-project/kubestock-core.git kubestock-core
fi

# Verify clone
echo "Repository contents:"
ls -la ~/kubestock-core/infrastructure/
EOF

# Step 5: Display next steps
echo ""
echo "=========================================="
echo "✅ Script 1 Complete!"
echo "=========================================="
echo ""
echo "Dev Server IP: $DEV_SERVER_IP"
echo ""
echo "Next: Run script 2 to deploy the cluster"
echo ""
echo "Option A - Run automatically:"
echo "  ssh -i $SSH_KEY ${SSH_USER}@${DEV_SERVER_IP} 'cd ~/kubestock-core/infrastructure/terraform/demo && chmod +x 2-deploy-cluster.sh && ./2-deploy-cluster.sh'"
echo ""
echo "Option B - SSH in and run manually:"
echo "  ssh -i $SSH_KEY ${SSH_USER}@${DEV_SERVER_IP}"
echo "  cd ~/kubestock-core/infrastructure/terraform/demo && chmod +x 2-deploy-cluster.sh && ./2-deploy-cluster.sh"
echo ""
