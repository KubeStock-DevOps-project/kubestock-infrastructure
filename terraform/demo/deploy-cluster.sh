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

# Copy demo inventory (force replace existing)
echo "📋 Copying demo inventory..."
rm -rf inventory/demo
cp -r ../kubespray-inventory-demo inventory/demo

# Ensure SSH key has correct permissions
echo "🔑 Setting SSH key permissions..."
chmod 600 ~/.ssh/id_ed25519

# Create Python virtual environment
echo "📦 Installing Python venv package..."
sudo apt install -y python3-venv python3-pip

echo "🐍 Setting up Python environment..."
python3 -m venv venv
source venv/bin/activate

# Install requirements
echo "📦 Installing Kubespray requirements..."
pip install -U pip
pip install -r requirements.txt

# Install Ansible collections
echo "📚 Installing Ansible collections..."
ansible-galaxy collection install ansible.utils community.crypto community.general ansible.netcommon ansible.posix community.docker kubernetes.core

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
