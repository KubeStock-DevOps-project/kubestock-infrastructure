# KubeStock Deployment Checklist

This checklist guides you through the complete deployment of the KubeStock infrastructure from scratch.

## 📋 Pre-Deployment Checklist

### AWS Account Setup
- [ ] AWS account created and accessible
- [ ] AWS CLI installed (`aws --version`)
- [ ] AWS credentials configured (`aws configure`)
- [ ] Billing alerts set up in AWS Console
- [ ] Service quotas checked for us-east-1:
  - [ ] VPCs: 5+ available
  - [ ] Elastic IPs: 5+ available
  - [ ] NAT Gateways: 5+ available
  - [ ] EC2 instances (t3.* family): 10+ available

### Local Environment Setup
- [ ] Terraform installed >= 1.5 (`terraform --version`)
- [ ] Git installed (`git --version`)
- [ ] SSH client available
- [ ] Code editor with Terraform support (optional)

### Network Requirements
- [ ] Know your public IP address (`curl ifconfig.me`)
- [ ] Stable internet connection
- [ ] No corporate VPN blocking AWS API calls

---

## 🔐 Step 1: Generate SSH Key Pair

```bash
# Generate SSH key for EC2 access
ssh-keygen -t rsa -b 4096 -f ~/.ssh/kubestock-dev-key -C "kubestock-dev"

# Set proper permissions
chmod 600 ~/.ssh/kubestock-dev-key
chmod 644 ~/.ssh/kubestock-dev-key.pub

# Verify key was created
ls -la ~/.ssh/kubestock-dev-key*
```

**Checklist:**
- [ ] Private key created: `~/.ssh/kubestock-dev-key`
- [ ] Public key created: `~/.ssh/kubestock-dev-key.pub`
- [ ] Permissions set correctly (600 for private, 644 for public)

---

## 📥 Step 2: Clone and Prepare Repository

```bash
# Clone the repository
cd ~/Projects
git clone <your-repo-url> kubestock-infrastructure
cd kubestock-infrastructure/terraform/dev

# Verify files
ls -la
```

**Checklist:**
- [ ] Repository cloned
- [ ] All .tf files present
- [ ] README.md exists
- [ ] terraform.tfvars.example exists

---

## ⚙️ Step 3: Configure Variables

```bash
# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars  # or vim, code, etc.
```

**Required values to fill in:**

```hcl
my_ip = "YOUR_PUBLIC_IP/32"  # e.g., "203.0.113.42/32"
rds_password = "YourSecurePassword123!"
ssh_public_key_path = "~/.ssh/kubestock-dev-key.pub"
```

**Checklist:**
- [ ] `terraform.tfvars` created
- [ ] `my_ip` set to your public IP with /32
- [ ] `rds_password` is strong (8+ chars, mixed case, numbers, symbols)
- [ ] `ssh_public_key_path` points to correct file
- [ ] File is NOT committed to git (check .gitignore)

---

## 🚀 Step 4: Initialize Terraform

```bash
# Initialize Terraform (downloads providers)
terraform init

# Expected output: "Terraform has been successfully initialized!"
```

**Checklist:**
- [ ] No errors during initialization
- [ ] `.terraform/` directory created
- [ ] `.terraform.lock.hcl` created
- [ ] AWS provider downloaded

**Troubleshooting:**
- If "backend configuration changed": Run `terraform init -reconfigure`
- If "provider not found": Check internet connection

---

## 🔍 Step 5: Review the Plan

```bash
# Generate and review execution plan
terraform plan

# Optionally save the plan
terraform plan -out=kubestock.tfplan
```

**Expected resources to be created:**
- ~40-50 resources total
- VPC, subnets, route tables
- Security groups (4)
- EC2 instances (2)
- Launch template + Auto Scaling Group
- RDS database
- Network Load Balancer
- Cognito User Pool
- IAM roles and policies

**Checklist:**
- [ ] Plan generated successfully
- [ ] No errors or warnings
- [ ] Resource count looks reasonable (~40-50)
- [ ] No unexpected deletions (should be all green +)

---

## ✅ Step 6: Apply Configuration

```bash
# Apply the configuration
terraform apply

# Review the plan one more time, then type 'yes' to confirm
```

**Estimated time:** 10-15 minutes

**What's being created:**
1. VPC and networking (1-2 min)
2. Security groups (30 sec)
3. NAT Gateway + EIP (2-3 min)
4. EC2 instances (2-3 min)
5. RDS database (5-8 min) ⏰ Longest step
6. Load balancer (2-3 min)
7. Cognito (30 sec)

**Checklist:**
- [ ] Applied successfully
- [ ] "Apply complete! Resources: XX added, 0 changed, 0 destroyed"
- [ ] No error messages
- [ ] Outputs displayed at the end

---

## 📊 Step 7: Verify Outputs

```bash
# View all outputs
terraform output

# View specific output
terraform output bastion_public_ip
terraform output k8s_api_endpoint
terraform output rds_endpoint

# View sensitive outputs
terraform output -json rds_password
```

**Checklist:**
- [ ] Bastion public IP is valid
- [ ] NLB DNS name is present
- [ ] RDS endpoint is reachable format
- [ ] Cognito User Pool ID exists
- [ ] All helper commands are populated

---

## 🔐 Step 8: Test SSH Access

```bash
# Get bastion IP
BASTION_IP=$(terraform output -raw bastion_public_ip)

# Test SSH to bastion
ssh -i ~/.ssh/kubestock-dev-key ubuntu@$BASTION_IP

# Inside bastion, test connection to control plane
CONTROL_PLANE_IP=$(terraform output -raw control_plane_private_ip)
ssh ubuntu@$CONTROL_PLANE_IP

# Exit both SSH sessions
exit
exit
```

**Checklist:**
- [ ] SSH to bastion successful
- [ ] SSH from bastion to control plane successful
- [ ] No permission denied errors
- [ ] No connection timeout errors

**Troubleshooting:**
- **Connection timeout**: Check security group rules and your current IP
- **Permission denied**: Check SSH key permissions (should be 600)
- **Host key verification failed**: Add `-o StrictHostKeyChecking=no` for first connection

---

## 🗄️ Step 9: Test Database Connection

```bash
# Port forward to RDS via bastion
BASTION_IP=$(terraform output -raw bastion_public_ip)
CONTROL_PLANE_IP=$(terraform output -raw control_plane_private_ip)
RDS_ADDRESS=$(terraform output -raw rds_address)

ssh -i ~/.ssh/kubestock-dev-key \
    -L 5432:$RDS_ADDRESS:5432 \
    -J ubuntu@$BASTION_IP \
    ubuntu@$CONTROL_PLANE_IP \
    -N &

# Test connection with psql (if installed locally)
psql -h localhost -p 5432 -U kubestock -d postgres

# Or use a GUI tool (DBeaver, pgAdmin) with:
# Host: localhost
# Port: 5432
# Database: postgres
# Username: kubestock
# Password: (from terraform.tfvars)
```

**Checklist:**
- [ ] Port forward established
- [ ] Database connection successful
- [ ] Can list databases (`\l` in psql)
- [ ] Kill port forward when done: `pkill -f "ssh.*5432"`

---

## 🌐 Step 10: Verify Load Balancer

```bash
# Get NLB DNS name
NLB_DNS=$(terraform output -raw nlb_dns_name)

# Test K8s API port (should timeout/refuse until K8s installed)
nc -zv $NLB_DNS 6443

# Check NLB target health in AWS Console
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names kubestock-dev-k8s-api-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)
```

**Checklist:**
- [ ] NLB is active
- [ ] Target is registered
- [ ] Target health will be unhealthy (K8s not installed yet - this is expected)

---

## 💰 Step 11: Verify Costs

```bash
# Check current month costs
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# Set up budget alert (if not done already)
# Go to: AWS Console > Billing > Budgets > Create budget
```

**Checklist:**
- [ ] Current costs visible in Cost Explorer
- [ ] Costs within expected range (~$10/day = ~$300/month)
- [ ] Budget alert configured for $800/month
- [ ] Billing alerts enabled

---

## 📝 Step 12: Document Deployment

Create a file with your deployment details:

```bash
cat > deployment-info.txt << EOF
# KubeStock Deployment Info
Date: $(date)
Region: us-east-1
AZ: us-east-1a

## Access
Bastion IP: $(terraform output -raw bastion_public_ip)
Control Plane: $(terraform output -raw control_plane_private_ip)
K8s API: $(terraform output -raw k8s_api_endpoint)
RDS Endpoint: $(terraform output -raw rds_endpoint)

## SSH Commands
Bastion: ssh -i ~/.ssh/kubestock-dev-key ubuntu@$(terraform output -raw bastion_public_ip)
Control Plane: $(terraform output -raw control_plane_ssh_via_bastion)
RDS Port Forward: $(terraform output -raw rds_port_forward_command)
EOF
```

**Checklist:**
- [ ] Deployment info saved
- [ ] File stored securely (not in git)
- [ ] Team members informed (if applicable)

---

## 🎯 Next Steps: Install Kubernetes

Your infrastructure is ready! Now you need to install Kubernetes using Kubespray:

### Option A: Quick Start (Recommended)

See the detailed guide: `KUBERNETES_SETUP.md` (create this file next)

### Option B: Manual Steps

1. **Prepare inventory**
   ```bash
   # SSH to bastion
   # Clone Kubespray on bastion or control plane
   # Create inventory with your node IPs
   ```

2. **Run Kubespray**
   ```bash
   ansible-playbook -i inventory/kubestock/hosts.yml cluster.yml
   ```

3. **Configure kubectl**
   ```bash
   # Copy kubeconfig from control plane
   # Test: kubectl get nodes
   ```

---

## 🧹 Cleanup (When Done)

If you need to destroy the infrastructure:

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy everything
terraform destroy

# Type 'yes' to confirm
```

**⚠️ WARNING**: This will delete ALL resources including the RDS database (no backups retained due to skip_final_snapshot).

**Checklist:**
- [ ] All important data backed up
- [ ] Confirmed you want to destroy
- [ ] Typed 'yes' to confirm
- [ ] All resources destroyed successfully
- [ ] Cost tracking stops within 24 hours

---

## ✅ Deployment Complete!

Congratulations! Your KubeStock infrastructure is now running. 

**Summary:**
- ✅ VPC and networking configured
- ✅ Bastion host accessible
- ✅ Control plane ready for Kubernetes
- ✅ Worker nodes ready (via ASG)
- ✅ RDS database online
- ✅ Load balancer configured
- ✅ IAM roles created
- ✅ Cognito ready for authentication

**What's working:**
- SSH access through bastion
- Private networking
- Database connectivity
- NAT for outbound traffic

**What's next:**
1. Install Kubernetes with Kubespray
2. Configure kubectl access
3. Deploy EBS CSI driver
4. Deploy AWS Load Balancer Controller
5. Deploy Cluster Autoscaler
6. Deploy your applications

---

## 📞 Support & Resources

- **Issues**: Check GitHub Issues
- **Documentation**: See README.md
- **Costs**: See COST_ANALYSIS.md
- **Terraform Docs**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **AWS Support**: https://console.aws.amazon.com/support/

---

**Happy Deploying! 🚀**
