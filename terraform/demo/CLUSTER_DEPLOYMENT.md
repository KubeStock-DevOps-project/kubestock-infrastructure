# Demo Cluster Deployment Guide

## SSH into Dev Server
```bash
ssh ubuntu@13.126.215.82
```

## Quick Start - Automated Deployment
```bash
# Download and run the deployment script
curl -O https://raw.githubusercontent.com/KubeStock-DevOps-project/kubestock-infrastructure/main/infrastructure/terraform/demo/deploy-cluster.sh
chmod +x deploy-cluster.sh
./deploy-cluster.sh
```

## Manual Step-by-Step (if you prefer)

### 1. Navigate to Kubespray
```bash
cd ~/kubestock-infrastructure/infrastructure/kubespray
```

### 2. Copy Demo Inventory
```bash
cp -r ../kubespray-inventory-demo inventory/demo
```

### 3. Setup Python Environment
```bash
python3 -m venv venv
source venv/bin/activate
pip install -U pip
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
```

### 4. Test Connectivity
```bash
ansible -i inventory/demo/hosts.ini all -m ping
```

### 5. Deploy Cluster (15-20 minutes)
```bash
ansible-playbook -i inventory/demo/hosts.ini cluster.yml -b
```

### 6. Configure kubectl Access
```bash
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown ubuntu:ubuntu ~/.kube/config
```

### 7. Verify Cluster
```bash
kubectl get nodes
kubectl get pods -A
```

## Cluster Info
- **Master**: 10.100.10.21
- **Workers**: 
  - 10.100.11.40
  - 10.100.12.40
  - 10.100.11.41
  - 10.100.12.41

## Troubleshooting

### SSH Key Issues
If you can't connect to nodes, check the SSH key:
```bash
ssh-add -l
ssh ubuntu@10.100.10.21  # Test from dev server to master
```

### Ansible Errors
If ansible fails to connect:
```bash
# Check inventory file
cat inventory/demo/hosts.ini

# Test individual node
ansible -i inventory/demo/hosts.ini master-1 -m ping
```

### Re-run Deployment
Safe to re-run if it fails:
```bash
ansible-playbook -i inventory/demo/hosts.ini cluster.yml -b
```
