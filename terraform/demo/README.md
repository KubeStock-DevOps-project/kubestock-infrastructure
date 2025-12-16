# KubeStock Demo Infrastructure

This is a complete demo environment for demonstrating cluster recreation and infrastructure provisioning.

## Quick Start (Automated Scripts)

The demo environment can be deployed using 4 automated scripts:

```bash
# Script 1: (Run from LOCAL machine) - Terraform + Dev Server Setup
cd infrastructure/terraform/demo
./1-setup-dev-server.sh
# This will SSH you into the dev server automatically

# Script 2: (Run from DEV SERVER) - Deploy Kubernetes Cluster
./2-deploy-cluster.sh

# Script 3: (Run from DEV SERVER) - Initialize Databases  
./3-init-databases.sh

# Script 4: (Run from DEV SERVER) - Deploy ArgoCD & Applications
./4-deploy-argocd.sh
```

## Key Differences from Production

### Infrastructure Changes
- **VPC CIDR**: `10.100.0.0/16` (completely isolated from production `10.0.0.0/16`)
- **Project Name**: `KubeStock-Demo` (all resources have `-demo` suffix)
- **Environment**: `demo`
- **Backend**: Local Terraform state (no S3 backend)
- **ECR**: Reuses existing production ECR repositories (no separate ECR created)

### Kubernetes Architecture
- **Control Plane**: 1 master node (vs 3 HA masters in production)
- **Worker Nodes**: 4 static worker nodes (vs Auto Scaling Group in production)
- **No ASG**: All nodes are static EC2 instances for demo simplicity

### Network Configuration
- **Public Subnets**: `10.100.1.0/24`, `10.100.2.0/24`, `10.100.3.0/24`
- **Private Subnets**: `10.100.10.0/24`, `10.100.11.0/24`, `10.100.12.0/24`
- **Control Plane IP**: `10.100.10.21`
- **Worker IPs**: 
  - worker-1: `10.100.10.30`
  - worker-2: `10.100.10.31`
  - worker-3: `10.100.11.30`
  - worker-4: `10.100.11.31`

### GitOps Configuration
- **GitOps Branch**: Uses `demo` branch of kubestock-gitops (not `main`)
- **No Cluster Autoscaler**: Removed since demo uses static nodes
- **AWS Secrets**: Uses `kubestock-demo/*` prefix in AWS Secrets Manager
  - `kubestock-demo/production/db`
  - `kubestock-demo/staging/db`
  - `kubestock-demo/production/asgardeo`
  - `kubestock-demo/staging/asgardeo`
  - `kubestock-demo/shared/test-runner`

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Your public IP address
3. Your SSH public key

## Setup Instructions

### Step 1: Configure Variables

1. Copy the template:
   ```bash
   cd infrastructure/terraform/demo
   cp terraform.tfvars.template terraform.tfvars
   ```

2. Edit `terraform.tfvars` and add:
   ```hcl
   my_ip = "YOUR_IP/32"  # e.g., "203.0.113.10/32"
   ssh_public_key_content = "ssh-rsa AAAAB3NzaC1... your-email@example.com"
   ```

### Step 2: Deploy Infrastructure

```bash
cd infrastructure/terraform/demo

# Initialize Terraform (local backend)
terraform init

# Review the plan
terraform plan -out=demo.tfplan

# Apply the infrastructure
terraform apply demo.tfplan
```

This will create:
- New VPC with completely isolated networking
- 1 bastion host
- 1 dev server (with Terraform, Ansible, and kubestock-infrastructure repo pre-installed)
- 1 Kubernetes master node
- 4 Kubernetes worker nodes
- RDS databases (production and staging)
- ALB, NLB, security groups, and all supporting infrastructure

### Step 3: SSH into Dev Server

```bash
# Get the dev server IP from Terraform outputs
terraform output dev_server_public_ip

# SSH into the dev server
ssh ubuntu@<dev-server-ip>

# The kubestock-infrastructure repo is already cloned at /home/ubuntu/kubestock-infrastructure
cd /home/ubuntu/kubestock-infrastructure
```

### Step 4: Run Ansible Playbook

On the dev server:

```bash
cd /home/ubuntu/kubestock-infrastructure/infrastructure/kubespray

# Install Kubespray dependencies
pip3 install -r requirements.txt

# Verify inventory
ansible-inventory -i ../../kubespray-inventory-demo/inventory/kubestock/hosts.ini --list

# Run the playbook
ansible-playbook -i ../../kubespray-inventory-demo/inventory/kubestock/hosts.ini \
  --become --become-user=root cluster.yml
```

## Ansible Inventory

The demo inventory is located at:
```
infrastructure/kubespray-inventory-demo/inventory/kubestock/
```

It contains:
- **1 master node**: master-1 (10.100.10.21)
- **4 worker nodes**: 
  - worker-1 (10.100.10.30)
  - worker-2 (10.100.10.31)
  - worker-3 (10.100.11.30)
  - worker-4 (10.100.11.31)

## Verification

After Ansible completes:

```bash
# SSH to master node via bastion
ssh -J ubuntu@<bastion-ip> ubuntu@10.100.10.21

# Check cluster status
kubectl get nodes
kubectl get pods -A
```

## Cleanup

To destroy the demo environment:

```bash
cd infrastructure/terraform/demo
terraform destroy
```

**Note**: This will delete all resources in the demo environment. The production environment is completely isolated and will not be affected.

## Important Notes

1. **Isolation**: This demo environment is completely isolated from production (different VPC, different CIDR ranges)
2. **ECR Sharing**: Uses existing production ECR repositories for container images
3. **IAM Resources**: All IAM roles/policies have `-demo` suffix to avoid conflicts
4. **No Remote State**: Uses local Terraform state file (not recommended for production)
5. **Static Nodes**: No auto-scaling - all nodes are static EC2 instances
6. **Single Master**: Not HA - single control plane node for simplicity
7. **GitOps Branch**: Uses `demo` branch of kubestock-gitops to avoid affecting production
8. **Separate Secrets**: Uses `kubestock-demo/*` prefix in AWS Secrets Manager

## ArgoCD Access

After running Script 4, ArgoCD will be available at:

```
URL: http://<master-ip>:32001
Username: admin
Password: (printed in script output)
```

To access from your local machine via SSH tunnel:
```bash
ssh -L 8080:10.100.10.21:32001 ubuntu@<dev-server-ip>
# Then open: http://localhost:8080
```

## Cost Optimization

The demo environment is designed to be cost-effective:
- Single master node (vs 3 in production)
- Static workers (no ASG overhead)
- Can be destroyed when not in use
- Reuses existing ECR (no duplicate image storage)

## Troubleshooting

### Terraform Issues
- Ensure AWS credentials are configured
- Check VPC CIDR doesn't conflict with existing VPCs
- Verify your IP address is correctly formatted

### Ansible Issues
- Verify SSH connectivity to all nodes
- Check inventory IP addresses match Terraform outputs
- Ensure dev server has network access to private subnets

### Connectivity Issues
- Verify security groups allow required traffic
- Check NAT Gateway is operational
- Ensure nodes have internet access for package installation
