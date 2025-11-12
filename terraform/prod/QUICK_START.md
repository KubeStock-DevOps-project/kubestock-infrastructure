# Quick Start Guide - KubeStock Production

## Prerequisites Checklist

- [ ] AWS Account with admin permissions
- [ ] AWS CLI configured (`aws configure`)
- [ ] Terraform >= 1.5 installed
- [ ] SSH key pair generated

---

## Step 1: Generate SSH Key

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/kubestock-prod-key -C "kubestock-prod"
```

---

## Step 2: Create S3 Bucket for Terraform State

```bash
# Create the S3 bucket (replace with your bucket name)
aws s3 mb s3://kubestock-terraform-state-prod --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket kubestock-terraform-state-prod \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket kubestock-terraform-state-prod \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket kubestock-terraform-state-prod \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

---

## Step 3: Update Backend Configuration

Edit `backend.tf` and replace the placeholder bucket name:

```hcl
terraform {
  backend "s3" {
    bucket = "kubestock-terraform-state-prod"  # Your actual bucket name
    key    = "prod/terraform.tfstate"
    region = "us-east-1"
  }
}
```

---

## Step 4: Create terraform.tfvars

```bash
# Copy the example file
cp terraform.tfvars.example terraform.tfvars

# Get your public IP
MY_IP=$(curl -4 -s ifconfig.me)
echo "Your IP: $MY_IP/32"

# Edit terraform.tfvars
nano terraform.tfvars
```

**Minimum required values:**
```hcl
my_ip                = "YOUR_IP_HERE/32"
rds_password         = "YOUR_STRONG_PASSWORD_HERE"
ssh_public_key_path  = "~/.ssh/kubestock-prod-key.pub"
```

---

## Step 5: Initialize Terraform

```bash
cd /home/dpiyumal/projects/KubeStock/kubestock-infrastructure/terraform/prod
terraform init
```

---

## Step 6: Plan the Deployment

```bash
terraform plan -out=tfplan
```

Review the plan carefully. You should see:
- 3 public subnets
- 3 private subnets
- 1 VPC
- 1 NAT Gateway
- Security groups
- EC2 instances (bastion, control plane)
- Auto Scaling Group
- RDS instance
- Cognito User Pool
- Network Load Balancer

---

## Step 7: Deploy Infrastructure

```bash
terraform apply tfplan
```

This will take approximately **10-15 minutes**.

---

## Step 8: Verify Deployment

```bash
# Get all outputs
terraform output

# Get specific outputs
terraform output bastion_public_ip
terraform output k8s_api_endpoint
terraform output rds_endpoint
```

---

## Step 9: Test Bastion Access

```bash
# Get bastion IP
BASTION_IP=$(terraform output -raw bastion_public_ip)

# SSH to bastion
ssh -i ~/.ssh/kubestock-prod-key ubuntu@$BASTION_IP
```

---

## Step 10: Access Control Plane

```bash
# Get IPs
BASTION_IP=$(terraform output -raw bastion_public_ip)
CONTROL_PLANE_IP=$(terraform output -raw control_plane_private_ip)

# SSH to control plane through bastion
ssh -i ~/.ssh/kubestock-prod-key -J ubuntu@$BASTION_IP ubuntu@$CONTROL_PLANE_IP
```

---

## Common Commands

### View Outputs
```bash
terraform output
terraform output -json > outputs.json
```

### Refresh State
```bash
terraform refresh
```

### Show Current State
```bash
terraform show
```

### Validate Configuration
```bash
terraform validate
```

### Format Code
```bash
terraform fmt -recursive
```

---

## Troubleshooting

### Issue: "Error creating EC2 Instance: UnauthorizedOperation"
**Solution**: Ensure your AWS credentials have EC2 creation permissions.

### Issue: "Error creating RDS Instance: DBSubnetGroupNotFoundFault"
**Solution**: Ensure the subnets exist before creating RDS. Run `terraform plan` to check dependencies.

### Issue: "Error: Invalid CIDR block"
**Solution**: Verify that subnet CIDRs don't overlap and are within the VPC CIDR range.

### Issue: SSH connection times out
**Solution**: 
1. Verify your `my_ip` variable is correct
2. Check security group rules
3. Ensure the instance is running

---

## Next Steps

After successful deployment:

1. **Install Kubernetes on Control Plane**
   - SSH to control plane
   - Install kubeadm, kubelet, kubectl
   - Initialize cluster

2. **Join Workers to Cluster**
   - Workers will auto-join via user_data (if configured)
   - Or manually join using `kubeadm join` command

3. **Configure kubectl Locally**
   ```bash
   terraform output kubectl_config_command
   # Run the command shown
   ```

4. **Install Kubernetes Addons**
   - AWS Load Balancer Controller
   - EBS CSI Driver
   - Cluster Autoscaler
   - Metrics Server

5. **Deploy Applications**
   - Deploy KubeStock backend
   - Deploy KubeStock frontend
   - Configure Cognito integration

---

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

⚠️ **WARNING**: This will:
- Delete all EC2 instances
- Delete the RDS database (a final snapshot will be created)
- Delete the VPC and all networking components
- This action cannot be undone

---

## Cost Monitoring

Estimated monthly cost for this configuration:
- **NAT Gateway**: ~$32/month
- **Bastion (t3.micro)**: ~$7/month
- **Control Plane (t3.medium)**: ~$30/month
- **Worker (t3.large)**: ~$60/month
- **RDS (db.t4g.medium)**: ~$50/month
- **NLB**: ~$16/month
- **Data Transfer & Storage**: ~$10/month

**Total**: ~$205/month

---

## Support

For issues or questions:
1. Check the README.md
2. Review CHECKLIST.md
3. See ADAPTATION_SUMMARY.md
4. Contact the DevOps team

---

**Environment**: Production  
**Project**: KubeStock  
**Last Updated**: 2025-11-13
