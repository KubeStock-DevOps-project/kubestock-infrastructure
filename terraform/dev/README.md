# KubeStock Development Infrastructure

This Terraform configuration creates a **lean, cost-optimized** AWS infrastructure for the KubeStock project. It's designed to fit within an **$800/month budget** and provides the foundation for a self-managed Kubernetes cluster (to be installed later with Kubespray/Ansible).

## 🎯 Design Philosophy

- **Single-AZ Deployment**: All resources in `us-east-1a` to minimize cross-AZ data transfer costs
- **Non-HA**: Single control plane, single NAT gateway, single-AZ RDS
- **Minimal Resource Sizes**: Smallest appropriate instance types
- **Auto-scaling Ready**: Worker ASG with conservative limits (min=1, desired=1, max=2)
- **Development-Grade**: Not production-ready, optimized for learning and development

## 📋 Architecture Overview

### Networking (Single-AZ)
- **1 VPC**: `10.0.0.0/16`
- **1 Public Subnet**: `10.0.1.0/24` (us-east-1a)
- **1 Private Subnet**: `10.0.10.0/24` (us-east-1a)
- **1 Internet Gateway**: For public internet access
- **1 NAT Gateway**: Single NAT for cost optimization
- **2 Route Tables**: One for public, one for private

### Compute
- **1 Bastion Host**: `t3.micro` in public subnet (SSH access point)
- **1 Control Plane**: `t3.medium` in private subnet (Kubernetes control plane)
- **1 Launch Template**: Defines `t3.large` worker configuration
- **1 Auto Scaling Group**: Worker nodes (min=1, desired=1, max=2)

### Security Groups
- **sg_bastion**: Port 22 from your IP only
- **sg_k8s_nodes**: All internal traffic between nodes, SSH from bastion
- **sg_rds**: Port 5432 from K8s nodes only
- **sg_nlb_api**: Port 6443 from bastion and your IP

### Managed Services
- **RDS PostgreSQL 16**: `db.t4g.medium`, single-AZ, 20GB storage
- **Network Load Balancer**: Exposes K8s API (port 6443)
- **Cognito User Pool**: Authentication service

### IAM
- **k8s-node-role**: Permissions for Cluster Autoscaler, EBS CSI, AWS LB Controller
- **k8s-node-profile**: Instance profile attached to all K8s nodes

## 💰 Estimated Monthly Cost (~$800)

| Resource | Type | Monthly Cost (est.) |
|----------|------|---------------------|
| Bastion Host | t3.micro | ~$7 |
| Control Plane | t3.medium | ~$30 |
| Worker Node (1x) | t3.large | ~$60 |
| RDS PostgreSQL | db.t4g.medium | ~$50 |
| NAT Gateway | Single NAT | ~$32 |
| Network Load Balancer | NLB | ~$18 |
| Data Transfer | Moderate | ~$20-50 |
| EBS Storage | ~150GB | ~$15 |
| **Total** | | **~$250-300** |

> **Note**: Actual costs may vary based on usage patterns. The configuration leaves significant budget headroom (~$500/month) for additional services, development activities, or unexpected overages.

## 🚀 Quick Start

### Prerequisites

1. **AWS Account** with appropriate credentials
2. **Terraform** >= 1.5
3. **SSH Key Pair** for EC2 access
4. **Your Public IP Address** for security group rules

### Step 1: Generate SSH Key

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/kubestock-dev-key -C "kubestock-dev"
```

### Step 2: Configure Variables

Create a `terraform.tfvars` file:

```hcl
aws_region        = "us-east-1"
availability_zone = "us-east-1a"
my_ip             = "YOUR_PUBLIC_IP/32"  # e.g., "203.0.113.42/32"
rds_password      = "SuperSecurePassword123!"
ssh_public_key_path = "~/.ssh/kubestock-dev-key.pub"
```

### Step 3: Initialize and Apply

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### Step 4: Access Your Infrastructure

```bash
# SSH to bastion
ssh -i ~/.ssh/kubestock-dev-key ubuntu@<BASTION_IP>

# SSH to control plane via bastion (from your local machine)
ssh -i ~/.ssh/kubestock-dev-key -J ubuntu@<BASTION_IP> ubuntu@<CONTROL_PLANE_PRIVATE_IP>

# Port forward to RDS
ssh -i ~/.ssh/kubestock-dev-key -L 5432:<RDS_ADDRESS>:5432 -J ubuntu@<BASTION_IP> ubuntu@<CONTROL_PLANE_PRIVATE_IP>
```

Use `terraform output` to get the exact commands with IPs filled in.

## 📦 What's Included

### ✅ Core Infrastructure
- [x] VPC with public and private subnets
- [x] Single NAT Gateway
- [x] Bastion host for secure access
- [x] Control plane EC2 instance
- [x] Worker nodes via Auto Scaling Group
- [x] RDS PostgreSQL database
- [x] Network Load Balancer for K8s API
- [x] Cognito User Pool for authentication
- [x] IAM roles for Kubernetes AWS controllers

### ❌ Intentionally Excluded
- [ ] SQS queues (use in-cluster messaging)
- [ ] EventBridge Scheduler (use K8s CronJobs)
- [ ] S3 buckets (create on-demand)
- [ ] Application Load Balancer (replaced with NLB)
- [ ] WAF (cost optimization)
- [ ] Multiple AZs (cost optimization)
- [ ] High availability components

## 🔧 Next Steps: Install Kubernetes

This Terraform configuration creates the **infrastructure foundation**. To install Kubernetes:

### Option 1: Kubespray (Recommended)

```bash
# Clone Kubespray
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray

# Install dependencies
pip install -r requirements.txt

# Copy inventory
cp -r inventory/sample inventory/kubestock

# Configure inventory with your IPs
# Edit inventory/kubestock/hosts.yml

# Deploy Kubernetes
ansible-playbook -i inventory/kubestock/hosts.yml cluster.yml
```

### Option 2: Manual Installation

You'll need to:
1. Install container runtime (containerd)
2. Install kubeadm, kubelet, kubectl
3. Initialize control plane
4. Join worker nodes
5. Install CNI (Calico, Cilium, etc.)
6. Install necessary controllers

## 🔒 Security Best Practices

1. **Rotate RDS Password**: Change it after initial deployment
2. **Restrict SSH Access**: Update `my_ip` to your actual IP
3. **Enable MFA**: For AWS console access
4. **Use Secrets Manager**: For storing sensitive credentials
5. **Enable CloudTrail**: For audit logging
6. **Regular Updates**: Keep AMIs and packages updated

## 📊 Monitoring & Observability

### Cost Monitoring
```bash
# View current costs
aws ce get-cost-and-usage \
  --time-period Start=2025-11-01,End=2025-11-30 \
  --granularity MONTHLY \
  --metrics BlendedCost
```

### Resource Monitoring
- Enable CloudWatch for EC2, RDS
- Set up billing alerts at $600, $700, $800
- Monitor NAT Gateway data transfer

## 🛠️ Useful Terraform Commands

```bash
# View outputs
terraform output

# View specific output
terraform output bastion_public_ip

# Destroy infrastructure
terraform destroy

# Refresh state
terraform refresh

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate
```

## 📝 Files Structure

```
terraform/dev/
├── main.tf              # Terraform & provider configuration
├── variables.tf         # Input variables
├── network.tf          # VPC, subnets, NAT, security groups
├── compute.tf          # EC2 instances, ASG, launch template
├── database.tf         # RDS PostgreSQL
├── iam.tf              # IAM roles and policies
├── load_balancer.tf    # NLB and Cognito
├── outputs.tf          # Output values
├── messaging.tf        # Empty (intentionally)
├── storage.tf          # Empty (intentionally)
├── schedular.tf        # Empty (intentionally)
└── README.md           # This file
```

## 🐛 Troubleshooting

### Issue: "No AMI found"
**Solution**: The data source looks for Ubuntu 22.04. Ensure you're in a region that has this AMI.

### Issue: "Resource limit exceeded"
**Solution**: Request limit increases in AWS Service Quotas.

### Issue: "SSH connection refused"
**Solution**: Check security group rules and ensure your IP hasn't changed.

### Issue: "RDS connection timeout"
**Solution**: Verify you're connecting through the bastion with port forwarding.

## 🤝 Contributing

This is a personal project, but suggestions are welcome! Please:
1. Test changes in a separate environment
2. Ensure cost implications are documented
3. Follow Terraform best practices

## 📄 License

MIT License - Use freely for learning and development.

## 🙏 Acknowledgments

- Based on lessons learned from a complex K3s project
- Optimized for the Kubespray deployment method
- Inspired by AWS best practices (with cost adaptations)

---

**⚠️ Important Reminders**:
- This is a **development environment**, not production-ready
- **No high availability** - single points of failure exist
- Monitor costs regularly to stay within budget
- Clean up resources when not in use to save costs
