# KubeStock Cluster Operations Guide

## Table of Contents
1. [Adding Worker Nodes](#adding-worker-nodes)
2. [Removing Worker Nodes](#removing-worker-nodes)
3. [Configuring Bastion for kubectl](#configuring-bastion-for-kubectl)
4. [Cluster Information](#cluster-information)

---

## Adding Worker Nodes

### 1. Create EC2 Instance via Terraform

Edit `/home/ubuntu/kubestock-infrastructure/terraform/prod/compute.tf`:

```terraform
# Increase the count parameter
resource "aws_instance" "worker" {
  count = 3  # Change from 2 to 3 to add one more worker
  ...
  
  # Update private_ip assignment logic for additional workers
  private_ip = count.index == 0 ? "10.0.11.30" : (count.index == 1 ? "10.0.12.30" : "10.0.10.30")
  ...
}
```

Apply Terraform changes:
```bash
cd /home/ubuntu/kubestock-infrastructure/terraform/prod
terraform apply
```

Note the private IP of the new worker from Terraform output.

### 2. Update Kubespray Inventory

Edit `/home/ubuntu/kubestock-infrastructure/kubespray/inventory/kubestock/hosts.ini`:

```ini
[all]
master-1 ansible_host=10.0.10.21 ansible_user=ubuntu etcd_member_name=etcd-1
worker-1 ansible_host=10.0.11.30 ansible_user=ubuntu
worker-2 ansible_host=10.0.12.30 ansible_user=ubuntu
worker-3 ansible_host=10.0.10.30 ansible_user=ubuntu  # NEW

[kube_control_plane]
master-1

[etcd]
master-1

[kube_node]
worker-1
worker-2
worker-3  # NEW

[k8s_cluster:children]
kube_control_plane
kube_node
```

### 3. Run Kubespray Scale Playbook

```bash
cd /home/ubuntu/kubestock-infrastructure/kubespray
ansible-playbook -i inventory/kubestock/hosts.ini scale.yml -b
```

This will:
- Install Kubernetes components on new nodes
- Configure containerd, kubelet, kube-proxy
- Join nodes to the cluster
- Deploy Calico CNI on new nodes
- Deploy EBS CSI driver daemonsets

### 4. Verify Node Joined

```bash
KUBECONFIG=~/kubeconfig kubectl get nodes -o wide
```

Expected output:
```
NAME       STATUS   ROLES           AGE   VERSION   INTERNAL-IP   
master-1   Ready    control-plane   2h    v1.34.1   10.0.10.21
worker-1   Ready    <none>          1h    v1.34.1   10.0.11.30
worker-2   Ready    <none>          1h    v1.34.1   10.0.12.30
worker-3   Ready    <none>          5m    v1.34.1   10.0.10.30
```

---

## Removing Worker Nodes

### 1. Drain and Delete Node from Kubernetes

```bash
# Drain node (evict pods gracefully)
KUBECONFIG=~/kubeconfig kubectl drain worker-3 --ignore-daemonsets --delete-emptydir-data

# Delete node from cluster
KUBECONFIG=~/kubeconfig kubectl delete node worker-3
```

### 2. Update Kubespray Inventory

Remove the node from `/home/ubuntu/kubestock-infrastructure/kubespray/inventory/kubestock/hosts.ini`:

```ini
[all]
master-1 ansible_host=10.0.10.21 ansible_user=ubuntu etcd_member_name=etcd-1
worker-1 ansible_host=10.0.11.30 ansible_user=ubuntu
worker-2 ansible_host=10.0.12.30 ansible_user=ubuntu
# worker-3 removed

[kube_node]
worker-1
worker-2
# worker-3 removed
```

### 3. Run Kubespray Remove Node Playbook (Optional)

For complete cleanup of Kubernetes artifacts on the node:

```bash
cd /home/ubuntu/kubestock-infrastructure/kubespray
ansible-playbook -i inventory/kubestock/hosts.ini remove-node.yml \
  -e node=worker-3 \
  -e delete_nodes_confirmation=yes \
  -b
```

### 4. Terminate EC2 Instance via Terraform

Edit `/home/ubuntu/kubestock-infrastructure/terraform/prod/compute.tf`:

```terraform
resource "aws_instance" "worker" {
  count = 2  # Reduce count
  ...
}
```

Apply changes:
```bash
cd /home/ubuntu/kubestock-infrastructure/terraform/prod
terraform apply
```

---

## Configuring Bastion for kubectl

The bastion host can be configured to run kubectl commands directly instead of always SSHing to the dev server.

### 1. SSH to Bastion

```bash
ssh -i ~/.ssh/kubestock-key ubuntu@100.30.61.159
```

### 2. Install kubectl

```bash
# Add Kubernetes repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubectl=1.34.1-1.1
sudo apt-mark hold kubectl
```

### 3. Copy kubeconfig from Control Plane

```bash
# Create .kube directory
mkdir -p ~/.kube

# Copy kubeconfig from control plane
scp ubuntu@10.0.10.21:~/.kube/config ~/.kube/config

# Verify
kubectl get nodes
```

### 4. Set Up SSH Tunnel for API Server (Alternative Method)

If NLB health checks are failing, use SSH tunnel:

```bash
# On bastion, create persistent SSH tunnel
ssh -i ~/.ssh/kubestock-key -L 6443:127.0.0.1:6443 ubuntu@10.0.10.21 -N -f

# Update kubeconfig to use localhost
sed -i 's|server:.*|server: https://127.0.0.1:6443|g' ~/.kube/config

# Test
kubectl get nodes
```

### 5. Install Useful Tools on Bastion (Optional)

```bash
# Install kubectx/kubens for context switching
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens

# Install k9s (terminal UI for Kubernetes)
VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep -Po '"tag_name": "v\K[^"]*')
curl -sL https://github.com/derailed/k9s/releases/download/v${VERSION}/k9s_Linux_amd64.tar.gz | \
  sudo tar xz -C /usr/local/bin k9s

# Install helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

---

## Cluster Information

### Current Architecture

**Control Plane:**
- **master-1**: 10.0.10.21 (us-east-1a private subnet)
  - t3.medium instance (2 vCPU, 4GB RAM, 30GB storage)
  - Runs: kube-apiserver, kube-controller-manager, kube-scheduler, etcd

**Worker Nodes:**
- **worker-1**: 10.0.11.30 (us-east-1b private subnet)
  - t3.medium instance (2 vCPU, 4GB RAM, 25GB storage)
- **worker-2**: 10.0.12.30 (us-east-1c private subnet)
  - t3.medium instance (2 vCPU, 4GB RAM, 25GB storage)

**Network:**
- **VPC**: 10.0.0.0/16
- **Private Subnets**: 10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24 (3 AZs)
- **Public Subnets**: 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24 (3 AZs)
- **NAT Gateway**: Single NAT in us-east-1a
- **NLB**: kubestock-nlb-api-b65eaa256bcf2be8.elb.us-east-1.amazonaws.com:6443

**Management Servers:**
- **Bastion**: 100.30.61.159 (public IP, always on)
- **Dev Server**: 13.223.102.35 (public IP, start/stop as needed)

### Kubernetes Version
- **Version**: v1.34.1
- **Container Runtime**: containerd 2.1.4
- **Network Plugin**: Calico

### Installed Add-ons
1. **AWS EBS CSI Driver**: Dynamic volume provisioning with gp3 default storage class
2. **NGINX Ingress Controller**: HTTP/HTTPS ingress (NodePort 30080/30443)
3. **ArgoCD**: GitOps continuous delivery
   - Access: Port-forward required
   - Password: `g4npBgErM8L01960`

### Important Commands

**From Dev Server (current setup):**
```bash
# Get nodes
KUBECONFIG=~/kubeconfig kubectl get nodes

# Get all pods
KUBECONFIG=~/kubeconfig kubectl get pods -A

# Get storage classes
KUBECONFIG=~/kubeconfig kubectl get sc

# Access ArgoCD
KUBECONFIG=~/kubeconfig kubectl port-forward -n argocd svc/argocd-server 8080:443
# Then visit https://localhost:8080
# Username: admin, Password: g4npBgErM8L01960
```

**SSH Commands:**
```bash
# SSH to bastion
ssh -i ~/.ssh/kubestock-key ubuntu@100.30.61.159

# SSH to control plane (via bastion)
ssh -i ~/.ssh/kubestock-key -J ubuntu@100.30.61.159 ubuntu@10.0.10.21

# SSH to worker-1 (via bastion)
ssh -i ~/.ssh/kubestock-key -J ubuntu@100.30.61.159 ubuntu@10.0.11.30

# SSH to worker-2 (via bastion)
ssh -i ~/.ssh/kubestock-key -J ubuntu@100.30.61.159 ubuntu@10.0.12.30
```

### Terraform Outputs

View all cluster information:
```bash
cd /home/ubuntu/kubestock-infrastructure/terraform/prod
terraform output
```

### Backup and Recovery

**etcd Backup:**
```bash
# On control plane
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/admin-master-1.pem \
  --key=/etc/ssl/etcd/ssl/admin-master-1-key.pem

# Copy to dev server
scp /tmp/etcd-backup.db ubuntu@13.223.102.35:~/backups/
```

**Kubernetes Manifests Backup:**
```bash
# From dev server, export all resources
KUBECONFIG=~/kubeconfig kubectl get all --all-namespaces -o yaml > all-resources-backup.yaml
```

### Cost Optimization

**Stop Dev Server when not in use:**
```bash
# Stop (saves ~$20-30/month)
aws ec2 stop-instances --instance-ids i-01867892022da09da

# Start when needed
aws ec2 start-instances --instance-ids i-01867892022da09da

# Get new public IP after start
aws ec2 describe-instances --instance-ids i-01867892022da09da \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
```

**Monthly Cost Estimate (Current Setup):**
- Control Plane (t3.medium): ~$30
- 2x Workers (t3.medium): ~$60
- Bastion (t2.micro): ~$9
- Dev Server (t3.large, if running): ~$60
- NAT Gateway: ~$32
- RDS PostgreSQL (db.t3.micro): ~$15
- **Total (with dev server): ~$206/month**
- **Total (dev server stopped): ~$146/month**

---

## Troubleshooting

### Node Not Ready
```bash
# Check node status
KUBECONFIG=~/kubeconfig kubectl describe node worker-X

# SSH to node and check kubelet
ssh -i ~/.ssh/kubestock-key -J ubuntu@100.30.61.159 ubuntu@10.0.X.X
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 100
```

### Pod Stuck in Pending
```bash
# Check pod events
KUBECONFIG=~/kubeconfig kubectl describe pod <pod-name> -n <namespace>

# Check node resources
KUBECONFIG=~/kubeconfig kubectl top nodes
```

### Network Issues
```bash
# Check Calico pods
KUBECONFIG=~/kubeconfig kubectl get pods -n kube-system -l k8s-app=calico-node

# Check Calico status on a node
ssh -i ~/.ssh/kubestock-key -J ubuntu@100.30.61.159 ubuntu@10.0.11.30
sudo calicoctl node status
```

### Storage Issues
```bash
# Check EBS CSI driver
KUBECONFIG=~/kubeconfig kubectl get pods -n kube-system -l app=ebs-csi-controller
KUBECONFIG=~/kubeconfig kubectl get pods -n kube-system -l app=ebs-csi-node

# Check PVCs
KUBECONFIG=~/kubeconfig kubectl get pvc -A
```

---

## Security Best Practices

1. **SSH Keys**: The cluster uses the key at `~/.ssh/kubestock-key` - keep this secure!
2. **Bastion Access**: Bastion has SSH access restricted to specific IPs (configurable in Terraform)
3. **API Server Access**: Control plane API is not directly exposed; access via bastion or dev server
4. **IAM Roles**: EC2 instances use IAM roles for AWS API access (no credentials stored on nodes)
5. **Network Segmentation**: Private subnets for Kubernetes nodes, public subnets only for bastion/dev
6. **Security Groups**: Properly configured to allow only required traffic between components

---

## References

- **Kubespray Documentation**: https://github.com/kubernetes-sigs/kubespray
- **Kubernetes Documentation**: https://kubernetes.io/docs/
- **Calico Documentation**: https://docs.tigera.io/calico/latest/about
- **AWS EBS CSI Driver**: https://github.com/kubernetes-sigs/aws-ebs-csi-driver
- **ArgoCD Documentation**: https://argo-cd.readthedocs.io/

---

**Last Updated**: November 13, 2025
**Cluster Version**: Kubernetes v1.34.1
**Infrastructure**: AWS us-east-1
