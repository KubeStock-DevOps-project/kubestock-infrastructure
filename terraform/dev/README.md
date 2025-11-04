# KubeStock Infrastructure - Dev Environment

Lean, cost-optimized AWS infrastructure for self-managed Kubernetes cluster.

## Quick Start

```bash
# 1. Generate SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/kubestock-dev-key

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit: my_ip, rds_password, ssh_public_key_path

# 3. Deploy
terraform init
terraform plan
terraform apply
```

## What Gets Created

- **VPC**: Single-AZ (us-east-1a) with public/private subnets
- **Compute**: Bastion (t3.micro), Control Plane (t3.medium), Worker ASG (t3.large, min=1, max=2)
- **Database**: RDS PostgreSQL 16 (db.t4g.medium, single-AZ)
- **Networking**: 1 NAT Gateway, NLB for K8s API
- **Auth**: Cognito User Pool
- **IAM**: Roles for Cluster Autoscaler, EBS CSI, AWS LB Controller

## Cost Estimate

~$250-320/month (well under $800 budget)

## Documentation

See `docs/` folder for detailed guides.

## Access

```bash
# SSH to bastion
ssh -i ~/.ssh/kubestock-dev-key ubuntu@$(terraform output -raw bastion_public_ip)

# View all access commands
terraform output helpful_commands
```
