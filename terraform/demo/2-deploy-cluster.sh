#!/bin/bash
# ========================================
# SCRIPT 2: Deploy Kubernetes Cluster
# ========================================
# Run from DEV SERVER after running script 1

set -euo pipefail

# Configuration - IPs are fixed in demo VPC (10.100.x.x)
# These are defined in terraform variables.tf and kubespray-inventory-demo/hosts.ini
MASTER_IP="10.100.10.21"
SSH_KEY="$HOME/.ssh/id_ed25519"

echo "=========================================="
echo "Demo Script 2: Deploy Kubernetes Cluster"
echo "=========================================="
echo "Master IP: $MASTER_IP"
echo ""

# Navigate to kubespray
cd ~/kubestock-core/infrastructure/kubespray

# Copy demo inventory
echo "📋 Step 1/7: Copying demo inventory..."
rm -rf inventory/demo 2>/dev/null || true
cp -r ../kubespray-inventory-demo inventory/demo

# Show inventory
echo "   Inventory contents:"
cat inventory/demo/hosts.ini | grep -E "^(master|worker)" || true

# Ensure SSH key has correct permissions
echo ""
echo "🔑 Step 2/7: Setting SSH key permissions..."
chmod 600 "$SSH_KEY"

# Install Python venv if needed
echo ""
echo "📦 Step 3/7: Installing Python dependencies..."
sudo apt update
sudo apt install -y python3-venv python3-pip

# Create Python virtual environment
echo ""
echo "🐍 Step 4/7: Setting up Python environment..."
python3 -m venv venv
source venv/bin/activate

# Install requirements
echo ""
echo "📦 Step 5/7: Installing Kubespray requirements..."
pip install -U pip
pip install -r requirements.txt

# Install Ansible collections
echo ""
echo "📚 Step 6/7: Installing Ansible collections..."
ansible-galaxy collection install ansible.utils community.crypto community.general ansible.netcommon ansible.posix community.docker kubernetes.core

# Test Ansible connectivity
echo ""
echo "🔌 Testing connectivity to cluster nodes..."
ansible -i inventory/demo/hosts.ini all -m ping

# Run the cluster deployment playbook
echo ""
echo "🚀 Step 7/7: Deploying Kubernetes cluster (this will take 15-20 minutes)..."
ansible-playbook -i inventory/demo/hosts.ini cluster.yml -b

echo ""
echo "✅ Ansible playbook complete!"
echo ""

# SSH into master and copy kubeconfig
echo "🔧 Configuring kubectl access on master..."
ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} << 'EOF'
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown ubuntu:ubuntu ~/.kube/config
echo "Testing kubectl on master..."
kubectl get nodes
EOF

# Copy kubeconfig to dev server
echo ""
echo "📋 Copying kubeconfig to dev server..."
mkdir -p ~/.kube
scp -o StrictHostKeyChecking=no ubuntu@${MASTER_IP}:~/.kube/config ~/.kube/config

# Verify cluster from dev server
echo ""
echo "🧪 Verifying cluster from dev server..."
kubectl get nodes
kubectl get pods -A

echo ""
echo "=========================================="
echo "✅ Kubernetes cluster deployed successfully!"
echo "=========================================="
echo ""
echo "Cluster nodes:"
kubectl get nodes -o wide
echo ""
echo "Next: Run script 3 to initialize databases"
echo "  cd ~/kubestock-core/infrastructure/terraform/demo && chmod +x 3-init-databases.sh && ./3-init-databases.sh"
echo ""
