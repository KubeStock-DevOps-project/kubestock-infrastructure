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

## Managing Developer Access

### Adding a New Developer

Each developer should have their own SSH key pair for security and audit purposes. **Never share private keys between team members.**

#### Step 1: Developer Generates SSH Key

The developer generates their own SSH key pair:

```bash
# On developer's local machine
ssh-keygen -t ed25519 -C "developer.name@kubestock.com" -f ~/.ssh/kubestock-dev

# This creates:
# ~/.ssh/kubestock-dev (private key - keep this secret!)
# ~/.ssh/kubestock-dev.pub (public key - share this with admin)
```

Developer sends their **public key** (`~/.ssh/kubestock-dev.pub`) to the admin.

#### Step 2: Admin Adds Developer's Public Key to Bastion

Admin logs into bastion and adds the developer's public key:

```bash
# SSH to bastion as admin
ssh -i ~/.ssh/kubestock-key ubuntu@100.30.61.159

# Add developer's public key to authorized_keys
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... developer.name@kubestock.com" >> ~/.ssh/authorized_keys

# Verify permissions
chmod 600 ~/.ssh/authorized_keys
```

#### Step 3: Developer Tests Access

Developer tests SSH access to bastion:

```bash
# Test SSH connection
ssh -i ~/.ssh/kubestock-dev ubuntu@100.30.61.159

# If successful, exit
exit
```

#### Step 4: Admin Provides Developer with kubeconfig

Admin copies kubeconfig and shares securely with the developer:

```bash
# On dev server, copy kubeconfig
cat ~/kubeconfig

# Share this file securely with developer (encrypted email, password manager, etc.)
# DO NOT commit kubeconfig to git or send via plain text
```

### Removing a Developer

When a developer leaves the team:

```bash
# SSH to bastion
ssh -i ~/.ssh/kubestock-key ubuntu@100.30.61.159

# Edit authorized_keys and remove their public key line
nano ~/.ssh/authorized_keys

# Save and exit
```

---

## Configuring kubectl Access for Developers

Developers use their local machines to access the cluster through the bastion as a secure tunnel/jump host.

### Prerequisites
- Your own SSH key pair generated and added to bastion (see above)
- kubectl installed on your local machine
- kubeconfig file provided by admin

### Step 1: Install kubectl on Your Local Machine

**macOS:**
```bash
brew install kubectl
```

**Linux:**
```bash
curl -LO "https://dl.k8s.io/release/v1.34.1/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

**Windows:** Download from [Kubernetes releases](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/)

Verify:
```bash
kubectl version --client
```

### Step 2: Save the kubeconfig File

The admin will provide you with a kubeconfig file. Save it:

```bash
# Create .kube directory
mkdir -p ~/.kube

# Save the kubeconfig content to this file
nano ~/.kube/kubestock-config
# Paste the kubeconfig content, save and exit

# Set proper permissions
chmod 600 ~/.kube/kubestock-config
```

**IMPORTANT**: The kubeconfig from the admin will have `server: https://10.0.10.21:6443` (direct control plane access for use within VPC). You need to change this to use the tunnel:

### Step 3: Update kubeconfig to Use Tunnel

Update the server address to use localhost (you'll tunnel to NLB):

```bash
export KUBECONFIG=~/.kube/kubestock-config
kubectl config set-cluster cluster.local --server=https://127.0.0.1:6443
```

**Why this change?**
- The dev server is inside the AWS VPC, so it connects directly to the control plane (10.0.10.21:6443)
- Your local machine is outside AWS, so you tunnel through bastion to the NLB, then to localhost (127.0.0.1:6443)

### Step 4: Configure SSH and Aliases

Add this to your `~/.ssh/config`:

```bash
cat >> ~/.ssh/config << 'EOF'

# KubeStock Bastion
Host kubestock
  HostName 100.30.61.159
  User ubuntu
  IdentityFile ~/.ssh/kubestock-dev
  ServerAliveInterval 60
  ServerAliveCountMax 3
  LocalForward 6443 10.0.10.21:6443
EOF
```

**Note**: Replace `~/.ssh/kubestock-dev` with the path to your private key file.

Add this to your `~/.bashrc` or `~/.zshrc`:

```bash
cat >> ~/.bashrc << 'EOF'

# KubeStock Cluster
export KUBECONFIG=~/.kube/kubestock-config
alias ks-start='ssh -f -N kubestock && echo "Tunnel started"'
alias ks-stop='pkill -f "ssh.*kubestock" && echo "Tunnel stopped"'
alias ks-status='ps aux | grep "ssh.*kubestock" | grep -v grep && echo "Tunnel is running" || echo "Tunnel is not running"'
alias k='kubectl'
alias kgn='kubectl get nodes'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
EOF

source ~/.bashrc
```

### Step 5: Start Using kubectl

```bash
# Start the tunnel
ks-start

# Use kubectl
kubectl get nodes
kubectl get pods -A
k top nodes  # Using the 'k' alias

# When done, stop the tunnel
ks-stop
```

### Testing Your Setup

After configuration, verify everything works:

```bash
# Check tunnel status
ks-status

# Start tunnel if not running
ks-start

# Test kubectl commands
kubectl get nodes
kubectl get pods -A
kubectl top nodes
kubectl cluster-info

# Stop tunnel when done
ks-stop
```

### Common kubectl Commands

```bash
# View cluster status
kubectl get nodes
kubectl get pods -A

# Check specific namespace
kubectl get pods -n kube-system

# View logs
kubectl logs -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name> -f  # Follow logs

# Execute commands in pods
kubectl exec -it -n <namespace> <pod-name> -- /bin/bash

# Port forwarding (for ArgoCD)
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Then visit: https://localhost:8080
# Username: admin, Password: g4npBgErM8L01960

# Resource usage
kubectl top nodes
kubectl top pods -A

# Apply/delete manifests
kubectl apply -f manifest.yaml
kubectl delete -f manifest.yaml
```

### SSH Access to Cluster Nodes

To SSH into cluster nodes (for troubleshooting):

```bash
# Add to your ~/.ssh/config
cat >> ~/.ssh/config << 'EOF'

# KubeStock Control Plane
Host ks-control
  HostName 10.0.10.21
  User ubuntu
  IdentityFile ~/.ssh/kubestock-dev
  ProxyJump kubestock

# KubeStock Workers
Host ks-worker-1
  HostName 10.0.11.30
  User ubuntu
  IdentityFile ~/.ssh/kubestock-dev
  ProxyJump kubestock

Host ks-worker-2
  HostName 10.0.12.30
  User ubuntu
  IdentityFile ~/.ssh/kubestock-dev
  ProxyJump kubestock
EOF
```

**Note**: Replace `~/.ssh/kubestock-dev` with the path to your private key file.

Usage:
```bash
ssh ks-control
ssh ks-worker-1
ssh ks-worker-2
```

### Optional: Install Additional Tools

**k9s** - Terminal UI for Kubernetes (recommended):
```bash
# macOS
brew install derailed/k9s/k9s

# Linux
curl -sL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz | \
  tar xz -C /tmp && sudo mv /tmp/k9s /usr/local/bin/

# Usage (with tunnel running)
k9s
```

**Helm** - Package manager:
```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Security Best Practices

1. **Each developer has their own SSH key** - never share private keys
2. **Always use tunnel through bastion** - never expose control plane directly
3. **Connect via NLB** - prepares for future HA control plane setup
4. **Stop tunnel when done** - use `ks-stop` to close connections
5. **Keep kubeconfig secure** - chmod 600, never commit to git
6. **Limit bastion access** - configure security group for your team's IPs only

### Troubleshooting

**Tunnel not working:**
```bash
# Check status
ks-status

# Restart tunnel
ks-stop
ks-start

# Test bastion connection
ssh kubestock echo "Connected!"
```

**kubectl connection refused:**
```bash
# Verify tunnel is running
ks-status

# Verify kubeconfig
kubectl config view | grep server
# Should show: https://127.0.0.1:6443

# Test NLB from bastion
ssh kubestock "curl -k https://kubestock-nlb-api-b65eaa256bcf2be8.elb.us-east-1.amazonaws.com:6443/healthz"
# Should return: ok
```

**Permission denied (publickey):**
```bash
# Verify your SSH key is added to bastion
# Contact admin to add your public key to bastion's ~/.ssh/authorized_keys
```

---

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

**From Dev Server (inside VPC):**
```bash
# Dev server connects directly to control plane (no tunnel needed)
KUBECONFIG=~/kubeconfig kubectl get nodes
KUBECONFIG=~/kubeconfig kubectl get pods -A
KUBECONFIG=~/kubeconfig kubectl get sc

# Access ArgoCD
KUBECONFIG=~/kubeconfig kubectl port-forward -n argocd svc/argocd-server 8080:443
# Then visit https://localhost:8080
# Username: admin, Password: g4npBgErM8L01960
```

**From Your Local Machine (outside VPC):**
```bash
# Start tunnel first
ks-start

# Then use kubectl
kubectl get nodes
kubectl get pods -A

# When done, stop tunnel
ks-stop
```

**SSH Commands:**
```bash
# SSH to bastion (admin using original key)
ssh -i ~/.ssh/kubestock-key ubuntu@100.30.61.159

# SSH to control plane (via bastion) - admin
ssh -i ~/.ssh/kubestock-key -J ubuntu@100.30.61.159 ubuntu@10.0.10.21

# SSH to worker-1 (via bastion) - admin
ssh -i ~/.ssh/kubestock-key -J ubuntu@100.30.61.159 ubuntu@10.0.11.30

# SSH to worker-2 (via bastion) - admin
ssh -i ~/.ssh/kubestock-key -J ubuntu@100.30.61.159 ubuntu@10.0.12.30

# For developers with their own keys, use their configured aliases:
# ssh ks-control, ssh ks-worker-1, ssh ks-worker-2
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
