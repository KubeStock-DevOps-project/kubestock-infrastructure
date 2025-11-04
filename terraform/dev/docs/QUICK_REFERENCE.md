# 🚀 KubeStock Infrastructure - Quick Reference

> **Lean, cost-optimized AWS infrastructure for self-managed Kubernetes**  
> Budget: $800/month | Actual: ~$250-320/month | Headroom: ~$480-550/month

---

## 📁 File Structure

```
terraform/dev/
├── 📄 main.tf                    # Terraform & AWS provider config
├── 📄 variables.tf                # Input variables with defaults
├── 📄 network.tf                  # VPC, subnets, NAT, security groups
├── 📄 compute.tf                  # EC2 instances, ASG, launch template
├── 📄 database.tf                 # RDS PostgreSQL
├── 📄 iam.tf                      # IAM roles & policies for K8s
├── 📄 load_balancer.tf            # NLB for K8s API + Cognito
├── 📄 outputs.tf                  # Output values (IPs, endpoints, etc.)
├── 📄 messaging.tf                # Empty (no SQS needed)
├── 📄 storage.tf                  # Empty (no S3 needed)
├── 📄 schedular.tf                # Empty (no EventBridge needed)
├── 📄 terraform.tfvars.example    # Template for your variables
├── 📄 .gitignore                  # Protect sensitive files
├── 📖 README.md                   # Main documentation
├── 📖 COST_ANALYSIS.md            # Detailed cost breakdown
├── 📖 DEPLOYMENT_CHECKLIST.md     # Step-by-step deployment guide
└── 📖 QUICK_REFERENCE.md          # This file
```

---

## ⚡ Quick Start (5 Minutes)

```bash
# 1. Generate SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/kubestock-dev-key

# 2. Get your public IP
curl ifconfig.me

# 3. Configure variables
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Fill in: my_ip, rds_password

# 4. Deploy
terraform init
terraform plan
terraform apply  # Takes ~10-15 minutes

# 5. Access
ssh -i ~/.ssh/kubestock-dev-key ubuntu@$(terraform output -raw bastion_public_ip)
```

---

## 🏗️ What Gets Created

### Networking (Single-AZ for cost)
- ✅ 1 VPC (10.0.0.0/16)
- ✅ 1 Public Subnet (10.0.1.0/24)
- ✅ 1 Private Subnet (10.0.10.0/24)
- ✅ 1 Internet Gateway
- ✅ 1 NAT Gateway (cost saver!)
- ✅ 2 Route Tables

### Compute
- ✅ 1 Bastion Host (t3.micro, public)
- ✅ 1 Control Plane (t3.medium, private)
- ✅ 1 Launch Template (t3.large workers)
- ✅ 1 Auto Scaling Group (min=1, desired=1, max=2)

### Security
- ✅ 4 Security Groups (bastion, k8s nodes, RDS, NLB)
- ✅ Least-privilege access rules
- ✅ SSH restricted to your IP only

### Managed Services
- ✅ RDS PostgreSQL 16 (db.t4g.medium, single-AZ)
- ✅ Network Load Balancer (K8s API on port 6443)
- ✅ Cognito User Pool + Client

### IAM
- ✅ K8s node role with policies for:
  - Cluster Autoscaler
  - EBS CSI Driver
  - AWS Load Balancer Controller
  - SSM (optional debugging)

---

## 💰 Cost Breakdown

| Category | Monthly Cost |
|----------|--------------|
| EC2 Compute | $98.70 |
| EBS Storage | $8.80 |
| RDS Database | $51.94 |
| Networking | $83.60 |
| Other | $5.00 |
| **TOTAL** | **~$248** |
| Budget | $800 |
| **Headroom** | **~$552** 💚 |

---

## 🔑 Essential Commands

### Terraform
```bash
# View all outputs
terraform output

# Get specific value
terraform output bastion_public_ip

# View state
terraform state list

# Destroy everything
terraform destroy
```

### SSH Access
```bash
# To bastion
ssh -i ~/.ssh/kubestock-dev-key ubuntu@<BASTION_IP>

# To control plane (via bastion)
ssh -i ~/.ssh/kubestock-dev-key -J ubuntu@<BASTION_IP> ubuntu@<CONTROL_PLANE_IP>

# Use output commands
terraform output bastion_ssh_command
terraform output control_plane_ssh_via_bastion
```

### Database
```bash
# Port forward to RDS
terraform output rds_port_forward_command | bash

# Connect with psql
psql -h localhost -p 5432 -U kubestock -d postgres
```

### AWS CLI
```bash
# View running instances
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=KubeStock" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# View current costs
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost
```

---

## 🎯 Next Steps

### 1. Verify Infrastructure
- [ ] SSH to bastion works
- [ ] SSH to control plane works
- [ ] RDS connection works
- [ ] NLB is healthy

### 2. Install Kubernetes
```bash
# Option A: Use Kubespray (recommended)
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
# ... follow Kubespray docs

# Option B: Manual kubeadm
# ... follow kubeadm docs
```

### 3. Configure Kubernetes
- [ ] Install CNI (Calico/Cilium)
- [ ] Install EBS CSI Driver
- [ ] Install AWS Load Balancer Controller
- [ ] Install Cluster Autoscaler
- [ ] Configure kubectl locally

### 4. Deploy Applications
- [ ] Create namespaces
- [ ] Deploy your services
- [ ] Set up ingress/load balancers
- [ ] Configure autoscaling

---

## 🚨 Troubleshooting

### Can't SSH to bastion
```bash
# Check security group
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=kubestock-dev-sg-bastion"

# Verify your IP
curl ifconfig.me

# Update security group if IP changed
# Edit terraform.tfvars and re-apply
```

### RDS connection timeout
```bash
# Verify security group allows access from K8s nodes
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=kubestock-dev-sg-rds"

# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier kubestock-dev-db
```

### High costs
```bash
# Check current spending
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# Review COST_ANALYSIS.md for optimization tips
```

### Worker nodes not scaling
```bash
# Check ASG
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names kubestock-dev-workers-asg

# Check desired capacity
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name kubestock-dev-workers-asg \
  --desired-capacity 2
```

---

## 📚 Documentation Links

| Document | Purpose |
|----------|---------|
| **README.md** | Complete overview, architecture, getting started |
| **COST_ANALYSIS.md** | Detailed cost breakdown, optimization strategies |
| **DEPLOYMENT_CHECKLIST.md** | Step-by-step deployment guide |
| **terraform.tfvars.example** | Template for your configuration |

### External Resources
- [AWS EC2 Pricing](https://aws.amazon.com/ec2/pricing/)
- [RDS Pricing](https://aws.amazon.com/rds/postgresql/pricing/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Kubespray Documentation](https://kubespray.io/)

---

## 🔒 Security Best Practices

- ✅ SSH restricted to your IP (`my_ip` variable)
- ✅ RDS in private subnet, no public access
- ✅ Bastion as single entry point
- ✅ IAM roles with least privilege
- ✅ Security groups with minimal rules
- ⚠️ Update `my_ip` if your IP changes
- ⚠️ Rotate RDS password regularly
- ⚠️ Enable MFA on AWS account

---

## 💡 Pro Tips

1. **Save on costs**: Stop instances when not in use
   ```bash
   # Stop control plane and workers (saves ~$90/month)
   aws ec2 stop-instances --instance-ids <INSTANCE_IDS>
   ```

2. **Quick access**: Add to ~/.ssh/config
   ```
   Host kubestock-bastion
       HostName <BASTION_IP>
       User ubuntu
       IdentityFile ~/.ssh/kubestock-dev-key
   
   Host kubestock-control
       HostName <CONTROL_PLANE_IP>
       User ubuntu
       IdentityFile ~/.ssh/kubestock-dev-key
       ProxyJump kubestock-bastion
   ```

3. **Monitor costs**: Set up AWS Budget alerts
   - Alert at 75% ($600)
   - Alert at 90% ($720)
   - Alert at 100% ($800)

4. **Use Spot Instances**: For workers (60-70% savings)
   ```hcl
   # Edit compute.tf
   mixed_instances_policy {
     instances_distribution {
       on_demand_percentage_above_base_capacity = 0
       spot_allocation_strategy = "lowest-price"
     }
   }
   ```

5. **Backup strategy**: For development
   - RDS snapshots before major changes
   - Terraform state in remote backend
   - Document manual changes

---

## 🎉 Success Criteria

Your deployment is successful when:

- ✅ `terraform apply` completes without errors
- ✅ You can SSH to bastion
- ✅ You can SSH to control plane via bastion
- ✅ RDS accepts connections
- ✅ NLB is active (even if unhealthy before K8s)
- ✅ Costs are within ~$10/day
- ✅ All outputs display correctly

---

## 📞 Getting Help

- **Issues**: Open a GitHub issue
- **Questions**: Check README.md first
- **Costs**: Review COST_ANALYSIS.md
- **Deployment**: Follow DEPLOYMENT_CHECKLIST.md
- **AWS Support**: Use AWS Support Center

---

**Version**: 1.0  
**Last Updated**: November 2025  
**Status**: Production-ready for development environments  

🎯 **Goal**: Lean infrastructure → Deploy Kubernetes → Build amazing things!
