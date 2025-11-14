# KubeStock Infrastructure

## Overview

Production Kubernetes infrastructure on AWS with **zero-trust security** and cost-optimized architecture:

- **Network**: 3-AZ High Availability (3 public + 3 private subnets)
- **Compute**: Single control plane + 2 static workers across AZs
- **Database**: Single-AZ RDS PostgreSQL 16
- **Security**: Fine-grained security groups with least privilege access

---

## Zero-Trust Security Model

### Access Patterns
- **Bastion** (t3.micro): kubectl operations only via NLB, direct RDS access
- **Dev Server** (t3.medium): SSH to all nodes, direct kubectl, Ansible/Terraform
- **Control Plane** + **Workers**: Inter-node communication via shared security group

### Security Groups (7 total)
```
my_ip → Bastion → NLB → Control Plane (kubectl)
my_ip → Dev Server → All Nodes (SSH)
Bastion → RDS (direct)
K8s Pods → RDS (application traffic)
```

**Key Rules**:
- ❌ Bastion **cannot** SSH to nodes (use dev server)
- ✅ Dev server can SSH to all nodes
- ✅ Bastion accesses kubectl via NLB (6443)
- ✅ Separate SGs for control plane, workers, inter-node traffic

---

## Architecture Summary

### Network (3-AZ HA)
- **VPC**: 10.0.0.0/16
- **Public Subnets**: 3 subnets across us-east-1a, us-east-1b, us-east-1c
- **Private Subnets**: 3 subnets across us-east-1a, us-east-1b, us-east-1c
- **NAT Gateway**: 1 NAT Gateway in us-east-1a (cost optimization)
- **Internet Gateway**: 1 IGW for public internet access

### Compute (Cost-Optimized)
- **Bastion**: 1x t3.micro (kubectl only)
- **Dev Server**: 1x t3.medium (SSH, Ansible, VS Code) - stop when not in use
- **Control Plane**: 1x t3.medium in us-east-1a
- **Workers**: 2x t3.large with static IPs (10.0.11.30, 10.0.12.30)

### Database
- **RDS PostgreSQL 16**: Single-AZ db.t4g.medium
- **Storage**: 20GB initial, auto-scales to 100GB

### Load Balancer
- **NLB**: Internal, in private subnets
- **Port**: 6443 (K8s API)
- **Target**: Control plane

---

## Prerequisites

1. AWS Account with admin permissions
2. Terraform >= 1.5
3. SSH key pair: `ssh-keygen -t rsa -b 4096 -f ~/.ssh/kubestock-key`
4. S3 bucket for state (update `backend.tf`)

---

## Quick Deploy

```bash
# 1. Create terraform.tfvars
cp terraform.tfvars.example terraform.tfvars

# 2. Edit with your values
nano terraform.tfvars
# Required: my_ip, rds_password, ssh_public_key_content

# 3. Deploy
terraform init
terraform plan
terraform apply
```

**Get SSH public key content:**
```bash
cat ~/.ssh/kubestock-key.pub
```

**For CI/CD**: Use `ssh_public_key_content` variable directly (no file path issues).

---

## Cost Breakdown

**Monthly Estimate**: ~$206/month
- NAT Gateway: $32
- Bastion (t3.micro): $7
- Dev Server (t3.medium): $30 (or $2 when stopped)
- Control Plane (t3.medium): $30
- Workers (2x t3.large): $120
- RDS (db.t4g.medium): $50
- NLB: $16
- Storage/Transfer: $10

**Save ~$28/month**: Stop dev server when not in use.

---

## Dev Server Management

```bash
# Stop (save money)
aws ec2 stop-instances --instance-ids $(terraform output -raw dev_server_instance_id)

# Start (when needed)
aws ec2 start-instances --instance-ids $(terraform output -raw dev_server_instance_id)

# Get new IP after start
terraform output dev_server_public_ip
```

---

## Security Groups (Zero-Trust)

| SG | Purpose | Ingress | Assigned To |
|----|---------|---------|-------------|
| `bastion` | kubectl operations | SSH (22) from my_ip | Bastion host |
| `dev_server` | SSH to nodes, Ansible | SSH (22) from my_ip | Dev server |
| `k8s_common` | Inter-node traffic | All ports from self | Control plane + Workers |
| `control_plane` | Control plane rules | SSH from dev_server, API (6443) from NLB + dev_server | Control plane |
| `workers` | Worker rules | SSH from dev_server, NodePort from NLB | Workers |
| `rds` | Database access | 5432 from bastion, control plane, workers | RDS |
| `nlb_api` | Load balancer | 6443 from bastion | NLB |

---

## Quick Access Guide

```bash
# SSH patterns
ssh ubuntu@<bastion-ip>              # ✅ kubectl via NLB
ssh ubuntu@<dev-server-ip>           # ✅ SSH to nodes, Ansible
ssh -J ubuntu@<dev-ip> ubuntu@<node> # ✅ Jump through dev server

# From bastion (kubectl only)
kubectl get nodes                    # ✅ Via NLB
psql -h <rds-endpoint>              # ✅ Direct RDS access
ssh ubuntu@<node>                    # ❌ Blocked

# From dev server (full access)
ssh ubuntu@<node>                    # ✅ SSH to any node
kubectl --server=https://<cp>:6443   # ✅ Direct API access
ansible-playbook site.yml            # ✅ Run playbooks
psql -h <rds-endpoint>              # ❌ Use bastion for DB
```

---

## Files

- `backend.tf` - S3 backend configuration
- `main.tf` - Provider configuration
- `variables.tf` - Input variables
- `network.tf` - VPC, subnets, security groups (zero-trust)
- `compute.tf` - EC2 instances
- `iam.tf` - IAM roles and policies
- `database.tf` - RDS PostgreSQL
- `cognito.tf` - Cognito user pool
- `load_balancer.tf` - Internal NLB
- `outputs.tf` - Output values

---

## Cleanup

```bash
terraform destroy
```

⚠️ **WARNING**: Deletes everything including RDS (final snapshot created).

---

## Troubleshooting

### Cannot SSH to nodes from bastion
**Expected behavior** - Use dev server instead.

### kubectl not working
Check NLB target health: `aws elbv2 describe-target-health --target-group-arn <arn>`

### Nodes can't communicate
Verify both specific SG + `k8s_common` SG assigned to each node.

---

**Project**: KubeStock | **Environment**: Production | **Managed By**: Terraform
