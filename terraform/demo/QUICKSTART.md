# Quick Start Guide - KubeStock Demo Environment

## 🚀 Quick Deployment

### 1. Prepare Credentials (2 minutes)

```bash
cd infrastructure/terraform/demo
cp terraform.tfvars.template terraform.tfvars
```

Fetch Asgardeo secrets from production:
```bash
./fetch-secrets.sh
# Copy the output to terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
my_ip = "YOUR_IP/32"  # Get your IP: curl ifconfig.me
ssh_public_key_content = "ssh-rsa AAAAB3NzaC1..."  # cat ~/.ssh/id_rsa.pub

# From fetch-secrets.sh output:
asgardeo_client_id     = "your-client-id"
asgardeo_client_secret = "your-client-secret"
asgardeo_base_url      = "https://api.asgardeo.io/t/your-org"
```

### 2. Deploy Infrastructure (15-20 minutes)

```bash
terraform init
terraform apply -auto-approve
```

### 3. Get Connection Details

```bash
# Save these outputs
terraform output bastion_public_ip
terraform output dev_server_public_ip
terraform output control_plane_private_ip
terraform output alb_dns_name  # Use this URL to access your app (HTTP)
```

**Access your application at:** `http://<alb_dns_name>`

### 4. Connect to Dev Server

```bash
ssh ubuntu@<dev-server-ip>
```

### 5. Deploy Kubernetes Cluster (20-30 minutes)

On dev server:

```bash
cd /home/ubuntu/kubestock-infrastructure/infrastructure/kubespray

# Install dependencies
pip3 install -r requirements.txt

# Deploy cluster
ansible-playbook -i ../../kubespray-inventory-demo/inventory/kubestock/hosts.ini \
  --become --become-user=root cluster.yml
```

### 6. Verify Cluster

SSH to master node:
```bash
ssh -J ubuntu@<bastion-ip> ubuntu@10.100.10.21
kubectl get nodes
kubectl get pods -A
```

## 📋 What You Get

- ✅ Completely isolated demo VPC (10.100.0.0/16)
- ✅ 1 master + 4 worker Kubernetes cluster
- ✅ Dev server with Terraform, Ansible, kubectl pre-installed
- ✅ RDS databases (production + staging)
- ✅ ALB with **HTTP access** (no SSL certificate needed)
- ✅ Full networking (NAT Gateway, subnets, security groups)
- ✅ IAM roles for CI/CD and observability
- ✅ All resources tagged with `-demo` suffix
- ✅ Asgardeo secrets auto-configured from production

## ⏱️ Total Time Estimate

- Infrastructure deployment: **15-20 minutes**
- Kubernetes cluster setup: **20-30 minutes**
- **Total: ~40 minutes** for complete cluster recreation

## 💰 Cost Optimization

Destroy when not in use:
```bash
cd infrastructure/terraform/demo
terraform destroy -auto-approve
```

## 🔍 Key Differences from Production

| Feature | Production | Demo |
|---------|-----------|------|
| VPC CIDR | 10.0.0.0/16 | 10.100.0.0/16 |
| Masters | 3 (HA) | 1 |
| Workers | ASG (2-8) | 4 static |
| ECR | Dedicated | Shared |
| State Backend | S3 | Local |
| Project Name | KubeStock | KubeStock-Demo |
| Domain/SSL | Custom domain + HTTPS | ALB DNS + HTTP |
| WAF | Enabled | Disabled |
| Secrets | AWS Console | terraform.tfvars |

## 📝 Troubleshooting

**Terraform fails with VPC conflict:**
- Ensure no other VPCs use 10.100.0.0/16

**Ansible can't reach nodes:**
- Verify bastion IP in outputs
- Check security groups allow SSH from dev server

**Cluster not forming:**
- Check all 5 nodes are running
- Verify network connectivity between nodes
- Review Kubespray logs

**Cannot fetch secrets:**
- Ensure AWS CLI is configured with proper credentials
- Verify you have access to production secrets
- Check the secret name: `kubestock/production/asgardeo`

## 🎯 Demo Checklist

- [ ] Infrastructure deployed successfully
- [ ] Can SSH to dev server
- [ ] Can SSH to master via bastion
- [ ] All 5 nodes visible in EC2 console
- [ ] Ansible playbook completed successfully
- [ ] `kubectl get nodes` shows 5 nodes (1 master, 4 workers)
- [ ] All pods in kube-system namespace running
- [ ] Can access app via ALB DNS URL (HTTP)

---

**Ready to demonstrate cluster recreation from scratch! 🎉**
