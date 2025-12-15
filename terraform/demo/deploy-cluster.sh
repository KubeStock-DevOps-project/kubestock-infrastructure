#!/bin/bash
# ========================================
# DEMO CLUSTER DEPLOYMENT SCRIPT
# ========================================
# Run this on the dev server to deploy the Kubernetes cluster

set -euo pipefail

echo "=========================================="
echo "KubeStock Demo Cluster Deployment"
echo "=========================================="

# Navigate to kubespray
cd ~/kubestock-core/infrastructure/kubespray

# Copy demo inventory
echo "📋 Copying demo inventory..."
cp -r ../kubespray-inventory-demo inventory/demo

# Create Python virtual environment
sudo apt install python3.10-venv -y

echo "🐍 Setting up Python environment..."
python3 -m venv venv
source venv/bin/activate

# Install requirements
echo "📦 Installing Kubespray requirements..."
pip install -U pip
pip install -r requirements.txt

# Install Ansible collections
echo "📚 Installing Ansible collections..."
ansible-galaxy collection install -r requirements.yml

# Test Ansible connectivity
echo "🔌 Testing connectivity to cluster nodes..."
ansible -i inventory/demo/hosts.ini all -m ping

# Run the cluster deployment playbook
echo "🚀 Deploying Kubernetes cluster (this will take 15-20 minutes)..."
ansible-playbook -i inventory/demo/hosts.ini cluster.yml -b

echo ""
echo "✅ Cluster deployment complete!"
echo ""
echo "To access the cluster:"
echo "1. Copy kubeconfig: mkdir -p ~/.kube && sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown ubuntu:ubuntu ~/.kube/config"
echo "2. Test: kubectl get nodes"
echo ""
