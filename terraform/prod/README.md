# KubeStock Production Infrastructure

## Overview

This Terraform configuration deploys the **KubeStock Production** infrastructure on AWS with a strategic hybrid approach:

- **Network**: **3-AZ High Availability** (3 public + 3 private subnets)
- **Compute**: **Non-HA "Sprint" Configuration** (1 control plane, 1 worker ASG for cost savings)
- **Database**: **Single-AZ RDS** (cost-optimized)

This setup provides a production-grade network foundation that can easily scale to full HA when needed, while keeping compute and database costs low during initial deployment.

---

## Architecture Summary

### Network (3-AZ HA)
- **VPC**: 10.0.0.0/16
- **Public Subnets**: 3 subnets across us-east-1a, us-east-1b, us-east-1c
- **Private Subnets**: 3 subnets across us-east-1a, us-east-1b, us-east-1c
- **NAT Gateway**: 1 NAT Gateway in us-east-1a (cost optimization)
- **Internet Gateway**: 1 IGW for public internet access

### Compute (Non-HA)
- **Bastion Host**: 1x t3.micro in public subnet (us-east-1a)
- **Control Plane**: 1x t3.medium in private subnet (us-east-1a)
- **Worker Nodes**: Auto Scaling Group (1 min, 1 desired, 3 max) spanning all 3 private subnets
  - Instance Type: t3.large
  - ASG spans 3 AZs for future HA, but starts with 1 worker for cost savings

### Database
- **RDS PostgreSQL 16**: Single-AZ db.t4g.medium in us-east-1a
- **Storage**: 20GB initial, auto-scales up to 100GB
- **Subnet Group**: Uses all 3 private subnets (AWS requirement)

### Load Balancer
- **Network Load Balancer**: Spans all 3 public subnets
- **Port**: 6443 (Kubernetes API)
- **Target**: Control Plane instance

### Authentication
- **AWS Cognito**: User Pool and Client for application authentication

### IAM
- **Node Role**: IAM role with policies for Cluster Autoscaler, EBS CSI, and AWS Load Balancer Controller

---

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **Terraform** >= 1.5 installed
3. **SSH Key Pair** generated:
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/kubestock-prod-key -C "kubestock-prod"
   ```
4. **S3 Bucket** for Terraform state (update `backend.tf` with actual bucket name)

---

## Deployment Steps

### 1. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
nano terraform.tfvars
```

**Required Variables:**
- `my_ip`: Your public IP (get with `curl -4 ifconfig.me`)
- `rds_password`: Strong password for RDS PostgreSQL
- `ssh_public_key_path`: Path to your SSH public key

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review the Plan

```bash
terraform plan
```

### 4. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm deployment.

---

## Post-Deployment

### Access Bastion Host

```bash
# SSH to bastion
ssh -i ~/.ssh/kubestock-prod-key ubuntu@<BASTION_PUBLIC_IP>
```

### Access Control Plane via Bastion

```bash
# SSH to control plane through bastion
ssh -i ~/.ssh/kubestock-prod-key -J ubuntu@<BASTION_PUBLIC_IP> ubuntu@<CONTROL_PLANE_PRIVATE_IP>
```

### Port Forward to RDS

```bash
# Forward local port 5432 to RDS
ssh -i ~/.ssh/kubestock-prod-key -L 5432:<RDS_ADDRESS>:5432 -J ubuntu@<BASTION_PUBLIC_IP> ubuntu@<CONTROL_PLANE_PRIVATE_IP>
```

### Get Outputs

```bash
# View all outputs
terraform output

# View specific output
terraform output bastion_public_ip
terraform output k8s_api_endpoint
```

---

## Cost Optimization Notes

This configuration is optimized for cost while maintaining a production-grade network:

1. **Single NAT Gateway**: All 3 private subnets route through 1 NAT Gateway (saves ~$64/month)
2. **Single Control Plane**: 1x t3.medium instead of 3 (saves ~$60/month)
3. **Single Worker**: ASG starts with 1 worker (saves ~$60/month)
4. **Single-AZ RDS**: No Multi-AZ replication (saves ~$40/month)

**Total Monthly Savings**: ~$224/month compared to full HA

---

## Scaling to Full HA

When ready to scale to full production HA:

1. **NAT Gateways**: Create 2 more NAT Gateways in us-east-1b and us-east-1c
2. **Control Plane**: Deploy 2 more control plane instances in us-east-1b and us-east-1c
3. **Workers**: Increase ASG `min_size` and `desired_capacity` to 3
4. **RDS**: Change `multi_az = true` in `database.tf`
5. **Update NLB**: Add additional control plane instances to the target group

---

## Security Groups

- **sg_bastion**: Port 22 from your IP
- **sg_k8s_nodes**: Port 22 from bastion, all traffic between nodes, port 6443 from NLB
- **sg_rds**: Port 5432 from K8s nodes only
- **sg_nlb_api**: Port 6443 from bastion and your IP

---

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**WARNING**: This will delete all resources including the RDS database. Make sure to take a final snapshot if needed.

---

## Files

- `backend.tf`: S3 backend configuration
- `main.tf`: Terraform and provider configuration
- `variables.tf`: Variable definitions
- `network.tf`: VPC, subnets, NAT, IGW, route tables, security groups
- `compute.tf`: EC2 instances, launch template, ASG
- `iam.tf`: IAM roles, policies, instance profile
- `database.tf`: RDS PostgreSQL
- `cognito.tf`: Cognito User Pool
- `load_balancer.tf`: Network Load Balancer for K8s API
- `outputs.tf`: Output values
- `terraform.tfvars.example`: Example variables file

---

## Support

For issues or questions, refer to the project documentation or contact the DevOps team.

---

**Project**: KubeStock  
**Environment**: Production  
**Managed By**: Terraform
