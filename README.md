# KubeStock Infrastructure

Production-grade Kubernetes infrastructure on AWS with **zero-trust security model** and automated CI/CD deployment via GitHub Actions.

[![Terraform](https://img.shields.io/badge/Terraform-1.13.5-purple?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-ap--south--1-orange?logo=amazon-aws)](https://aws.amazon.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Self--Managed-blue?logo=kubernetes)](https://kubernetes.io/)

---

## 📋 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [Zero-Trust Security Model](#-zero-trust-security-model)
- [Infrastructure Components](#-infrastructure-components)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [CI/CD Workflows](#-cicd-workflows)
- [Contributing](#-contributing)
- [Cost Breakdown](#-cost-breakdown)
- [Management Operations](#-management-operations)

---

## 🏗️ Architecture Overview

**High-Level Design:**
- **Network**: 3-AZ High Availability VPC (3 public + 3 private subnets)
- **Compute**: 
  - 1x Bastion Host (t3.micro) - kubectl operations only
  - 1x Dev Server (t3.medium) - SSH gateway, Ansible, Terraform
  - 1x Control Plane (t3.medium) - Kubernetes master in ap-south-1a
  - 2x Worker Nodes (t3.medium) - Static instances across ap-south-1b and ap-south-1c
- **Container Registry**: 5x ECR repositories for microservices (lifecycle policy: keep last 5 images)
- **Load Balancer**: Internal NLB for Kubernetes API (port 6443)
- **NAT Gateway**: Single NAT in ap-south-1a for cost optimization
- **CI/CD**: GitHub Actions with OIDC for automated infrastructure deployment and container image pushes

**Key Design Decisions:**
- ✅ **No Auto Scaling Groups** - Static worker nodes managed via Ansible/Kubespray
- ✅ **Fixed Private IPs** - Predictable addressing for Ansible inventory
- ✅ **Single Control Plane** - Cost-optimized setup (can scale to 3 for full HA)
- ✅ **Dev Server** - Stop when not in use to save ~$28/month

---

## 🔒 Zero-Trust Security Model

### Access Control Matrix

| Resource | SSH Access | Kubectl Access | ECR Access |
|----------|-----------|----------------|------------|
| **Bastion** | ✅ From anywhere (0.0.0.0/0) | ✅ Via NLB | ❌ |
| **Dev Server** | ✅ From `MY_IP` only | ✅ Direct to control plane | ❌ |
| **Control Plane** | ✅ From dev server | N/A | ✅ Pull only |
| **Workers** | ✅ From dev server | N/A | ✅ Pull only |
| **GitHub Actions** | N/A | N/A | ✅ Push only (OIDC) |

### Security Groups (6 Groups)

```
Internet → Bastion (0.0.0.0/0:22)
MY_IP → Dev Server (MY_IP:22)
Dev Server → All K8s Nodes (SSH:22)
Bastion → NLB → Control Plane (K8s API:6443)
K8s Nodes ↔ K8s Nodes (all ports via k8s_common SG)
```

**Critical Rules:**
- ❌ Bastion **cannot** SSH to K8s nodes (use dev server)
- ✅ Dev server can SSH to all nodes for configuration management
- ✅ Inter-node communication via shared `k8s_common` security group
- ✅ All external access requires authentication (SSH keys)

---

## 🧩 Infrastructure Components

### Networking
- **VPC**: `10.0.0.0/16`
- **Public Subnets**: 
  - `10.0.1.0/24` (ap-south-1a) - Bastion, Dev Server
  - `10.0.2.0/24` (ap-south-1b)
  - `10.0.3.0/24` (ap-south-1c)
- **Private Subnets**: 
  - `10.0.10.0/24` (ap-south-1a) - Control Plane
  - `10.0.11.0/24` (ap-south-1b) - Worker 1
  - `10.0.12.0/24` (ap-south-1c) - Worker 2
- **NAT Gateway**: Single NAT in ap-south-1a (saves ~$64/month vs 3 NATs)
- **Internet Gateway**: Single IGW for public subnet internet access

### Compute Instances

| Instance | Type | Subnet | IP | Purpose |
|----------|------|--------|-----|---------|
| Bastion | t3.micro | Public (ap-south-1a) | Elastic IP | kubectl via NLB |
| Dev Server | t3.medium | Public (ap-south-1a) | Dynamic (free) | SSH gateway, Ansible, Terraform |
| Control Plane | t3.medium | Private (ap-south-1a) | `10.0.10.21` | Kubernetes master |
| Worker 1 | t3.medium | Private (ap-south-1b) | `10.0.11.30` | Kubernetes worker |
| Worker 2 | t3.medium | Private (ap-south-1c) | `10.0.12.30` | Kubernetes worker |

**Note:** Dev server has no Elastic IP - public IP changes on start/stop but costs $0 when stopped.

### Container Registry (ECR)
- **Repositories**: 5 microservices
  - `ms-product-catalog`
  - `ms-inventory`
  - `ms-supplier`
  - `ms-order-management`
  - `ms-test`
- **Lifecycle Policy**: Keep last 5 images per repository
- **Features**: Image scanning on push, AES256 encryption
- **Access**: GitHub Actions (push via OIDC), K8s nodes (pull via IAM instance profile)

### Load Balancer
- **Type**: Network Load Balancer (NLB)
- **Scheme**: Internal (not internet-facing)
- **Subnets**: All 3 private subnets
- **Port**: 6443 → Control Plane
- **Health Checks**: TCP on port 6443 every 30s

### IAM Roles
- **kubestock-node-role**: Instance profile for control plane and workers
  - SSM Session Manager access
  - Kubernetes AWS controllers (Cluster Autoscaler, EBS CSI, AWS LB Controller)
  - ECR pull access
- **KubeStock-github-actions-ecr-role**: OIDC role for GitHub Actions
  - ECR push permissions (all microservice repositories)
  - Trust policy: restricted to specific repos and production environment
  - Used by CI/CD pipelines to push container images

---

## 📦 Prerequisites

1. **AWS Account** with admin permissions
2. **Terraform** >= 1.13.5 ([Install](https://www.terraform.io/downloads))
3. **AWS CLI** configured with credentials
4. **SSH Key Pair**:
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/kubestock-key
   ```
5. **S3 Backend** (optional): For remote state storage
   - Create S3 bucket: `kubestock-terraform-state`
   - Configure in `terraform/base/main.tf`

---

## 🚀 Quick Start

### Local Deployment

```bash
# 1. Clone repository
git clone https://github.com/KubeStock-DevOps-project/kubestock-infrastructure.git
cd kubestock-infrastructure/terraform/prod

# 2. Create terraform.tfvars
cat > terraform.tfvars <<EOF
my_ip = "$(curl -4 ifconfig.me)/32"
ssh_public_key_content = "$(cat ~/.ssh/kubestock-key.pub)"
EOF

# 3. Initialize and deploy
terraform init
terraform plan
terraform apply
```

### Get Outputs

```bash
# Connection details
terraform output bastion_public_ip
terraform output dev_server_public_ip
terraform output control_plane_private_ip
terraform output worker_private_ips
terraform output nlb_dns_name

# ECR repositories
terraform output ecr_repository_urls
terraform output github_actions_role_arn
```

---

## ⚙️ CI/CD Workflows

### Workflow Files

1. **`terraform-pr-checks.yml`** - Runs on Pull Requests
   - Terraform format check
   - Terraform validate (no backend required)
   - Ensures code quality before merge

2. **`terraform-prod-apply.yml`** - Runs on Push to Main
   - Generates `terraform.tfvars` from GitHub secrets
   - Terraform format check
   - Terraform init (with AWS backend)
   - Terraform validate
   - Terraform plan
   - Terraform apply (auto-approved)

### Required GitHub Secrets & Variables

**Set in**: Repository Settings → Secrets and variables → Actions

#### Variables (non-sensitive):
- `AWS_REGION` - Deployment region (e.g., `ap-south-1`)
- `MY_IP` - Your public IP with CIDR (e.g., `1.2.3.4/32`)

#### Secrets (sensitive):
- `SSH_PUBLIC_KEY_CONTENT` - SSH public key (full content)

**Note**: GitHub Actions uses OIDC for AWS authentication. Configure the following IAM roles:
- `KubeStock-Terraform-Plan-Role` - For PR checks (read-only)
- `KubeStock-Terraform-Apply-Role` - For deployments (read-write)
- `KubeStock-github-actions-ecr-role` - For ECR push operations

**Documentation**: See [`.github/GITHUB_SECRETS_SETUP.md`](.github/GITHUB_SECRETS_SETUP.md) for detailed setup instructions.

### Deployment Flow

```
Feature Branch → PR → PR Checks Pass → Merge to Main → Terraform Apply
```

**Safety Features:**
- Format and validation on every PR
- Concurrency control prevents overlapping applies
- Terraform plan review before apply
- All secrets encrypted and hidden in logs

---

## 🤝 Contributing

### Infrastructure Changes

All infrastructure modifications must follow the **zero-trust security model** and require approval from the infrastructure team.

#### Process:

1. **Create Feature Branch**
   ```bash
   git checkout -b feature/add-monitoring
   ```

2. **Make Changes** (follow zero-trust principles)
   - Update Terraform files in `terraform/prod/`
   - Add security group rules with least privilege
   - Document changes in commit messages

3. **Open Pull Request**
   - PR triggers automated checks (fmt + validate)
   - Request review from [@KubeStock-DevOps-project/infrastructure](https://github.com/orgs/KubeStock-DevOps-project/teams/infastructure)
   - Address feedback

4. **Wait for Approval**
   - Infrastructure team reviews security implications
   - Minimum 1 approval required

5. **Merge to Main**
   - Automated deployment triggers
   - Monitor GitHub Actions for apply status

### Zero-Trust Guidelines

When proposing infrastructure changes:

✅ **DO:**
- Use security groups with specific source/destination
- Limit SSH access to dev server only
- Add egress rules only when necessary
- Document security group changes clearly
- Test in a separate environment first

❌ **DON'T:**
- Open ports to `0.0.0.0/0` (except bastion SSH)
- Allow unrestricted egress (`0.0.0.0/0` on all ports)
- Bypass the PR review process
- Commit `terraform.tfvars` with secrets
- Create IAM roles with `*` permissions

---

## 💰 Cost Breakdown

**Monthly Estimate**: ~$147/month (with dev server stopped)

| Resource | Spec | Monthly Cost |
|----------|------|--------------|
| NAT Gateway | 1x in ap-south-1a | $32 |
| Bastion | t3.micro (24/7) | $7 |
| Dev Server | t3.medium (stopped) | $2 (storage only) |
| Control Plane | t3.medium (24/7) | $30 |
| Worker 1 | t3.medium (24/7) | $30 |
| Worker 2 | t3.medium (24/7) | $30 |
| NLB | Internal NLB | $16 |
| ECR | 5 repositories | <$1 (storage only) |
| Storage/Transfer | EBS + Data | ~$10 |

**Cost Optimization Tips:**
- Stop dev server when not in use: **saves $28/month**
- Use Spot Instances for workers: **saves ~40%** (requires setup)
- ECR lifecycle policies: automatically remove old images to minimize storage costs
- Monitor NAT Gateway data transfer in ap-south-1a: largest variable cost
- Review ECR image scanning costs if pushing frequently

---

## 🛠️ Management Operations

### Dev Server Operations

**Stop (save money):**
```bash
aws ec2 stop-instances --instance-ids $(terraform output -raw dev_server_instance_id)
```

**Start (when needed):**
```bash
aws ec2 start-instances --instance-ids $(terraform output -raw dev_server_instance_id)

# Get new public IP after start
terraform refresh
terraform output dev_server_public_ip
```

### SSH Access Patterns

**Connect to bastion:**
```bash
ssh -i ~/.ssh/kubestock-key ubuntu@<bastion-eip>
```

**Connect to dev server:**
```bash
ssh -i ~/.ssh/kubestock-key ubuntu@<dev-server-ip>
```

**SSH to K8s nodes (via dev server jump host):**
```bash
# Add key to SSH agent
ssh-add ~/.ssh/kubestock-key

# Jump through dev server
ssh -J ubuntu@<dev-server-ip> ubuntu@10.0.10.21  # Control plane
ssh -J ubuntu@<dev-server-ip> ubuntu@10.0.11.30  # Worker 1
ssh -J ubuntu@<dev-server-ip> ubuntu@10.0.12.30  # Worker 2
```

### Kubectl Access

**From bastion (via NLB):**
```bash
ssh ubuntu@<bastion-eip>
kubectl --kubeconfig ~/.kube/config get nodes
```

**From dev server (direct):**
```bash
ssh ubuntu@<dev-server-ip>
kubectl --server=https://10.0.10.21:6443 --kubeconfig ~/.kube/config get nodes
```

### ECR Access

**Login to ECR (from any K8s node):**
```bash
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-south-1.amazonaws.com
```

**GitHub Actions (automatic via OIDC):**
```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}  # KubeStock-github-actions-ecr-role
    aws-region: ap-south-1

- name: Login to Amazon ECR
  uses: aws-actions/amazon-ecr-login@v2
```

---

## 📚 Additional Documentation

- **Cost Analysis**: `terraform/prod/docs/COST_ANALYSIS.md`
- **Deployment Checklist**: `terraform/prod/docs/DEPLOYMENT_CHECKLIST.md`
- **Quick Reference**: `terraform/prod/docs/QUICK_REFERENCE.md`
- **GitHub Secrets Setup**: `.github/GITHUB_SECRETS_SETUP.md`

---

## 🧹 Cleanup

```bash
cd terraform/prod
terraform destroy
```

⚠️ **WARNING**: This will delete all resources including:
- All EC2 instances
- ECR repositories and container images
- VPC and networking components
- Load balancer and NAT gateway
- IAM roles and policies

---

## 📝 License

This project is maintained by the [KubeStock Infrastructure Team](https://github.com/orgs/KubeStock-DevOps-project/teams/infastructure).

---

## 🆘 Troubleshooting

### Cannot SSH to K8s nodes from bastion
**Expected behavior** - Use dev server as SSH gateway instead.

### Kubectl connection timeout
Check NLB target health:
```bash
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw k8s_api_target_group_arn)
```

### Nodes cannot communicate
Verify both specific SG + `k8s_common` SG are attached:
```bash
aws ec2 describe-instances --instance-ids <instance-id> --query 'Reservations[0].Instances[0].SecurityGroups'
```

### Terraform apply fails in GitHub Actions
1. Verify all secrets/variables are set in GitHub
2. Check AWS credentials are valid
3. Review GitHub Actions logs for specific error
4. Ensure no manual changes conflict with Terraform state

---

**Project**: KubeStock | **Environment**: Production | **Managed By**: Terraform + GitHub Actions
