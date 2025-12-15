# Production vs Demo - Configuration Comparison

## Infrastructure Comparison

| Component | Production | Demo | Reason |
|-----------|-----------|------|--------|
| **VPC CIDR** | `10.0.0.0/16` | `10.100.0.0/16` | Complete network isolation |
| **Public Subnets** | `10.0.1-3.0/24` | `10.100.1-3.0/24` | Aligned with VPC change |
| **Private Subnets** | `10.0.10-12.0/24` | `10.100.10-12.0/24` | Aligned with VPC change |
| **Project Name** | `KubeStock` | `KubeStock-Demo` | Resource name conflict prevention |
| **Environment** | `production` | `demo` | Clear environment distinction |
| **Terraform Backend** | S3 (remote) | Local | Simplify demo setup |
| **ECR Repositories** | Created | Reused from prod | No duplicate image storage |

## Kubernetes Topology

| Component | Production | Demo | Reason |
|-----------|-----------|------|--------|
| **Control Plane** | 3 nodes (HA) | 1 node | Demo simplicity |
| **Control Plane IPs** | `10.0.10.21`, `10.0.11.21`, `10.0.12.21` | `10.100.10.21` | Network alignment |
| **Worker Nodes** | ASG (2-8 dynamic) | 4 static | No auto-scaling needed |
| **Worker IPs** | Dynamic (ASG) | `10.100.10.30-31`, `10.100.11.30-31` | Static for demo |
| **etcd** | 3-member cluster | 1-member | HA not needed for demo |

## Resource Names (Examples)

| Resource Type | Production | Demo |
|--------------|-----------|------|
| **IAM Role** | `kubestock-node-role` | `kubestock-demo-node-role` |
| **Key Pair** | `kubestock-key` | `kubestock-demo-key` |
| **Security Group** | `kubestock-workers-sg` | `kubestock-demo-workers-sg` |
| **RDS Instance** | `kubestock-prod-db` | `kubestock-demo-prod-db` |
| **Lambda Function** | `kubestock-token-refresh` | `kubestock-demo-token-refresh` |
| **S3 Bucket** | `kubestock-observability-*` | `kubestock-demo-observability-*` |

## Module Configuration

| Module | Production | Demo | Changes |
|--------|-----------|------|---------|
| **networking** | Standard | Same | VPC CIDR only |
| **security** | Standard | Same | VPC reference only |
| **compute** | Standard | `+ git clone` | Dev server user data |
| **kubernetes** | ASG enabled | ASG disabled | `static_worker_count=4` |
| **ecr** | Enabled | **Disabled** | Commented out |
| **cicd** | Uses module.ecr | `ecr_repository_arns=[]` | No ECR dependency |
| **rds** | Standard | Same | Project name only |
| **alb** | `worker_asg_name` set | `worker_asg_name=""` | Use static IPs |
| **dns** | Standard | Same | Domain name updated |
| **lambda** | Standard | Same | Project name only |
| **secrets** | Standard | Same | Project name only |
| **observability** | Standard | Same | Project name only |

## Variables Changed

### Network Configuration
```hcl
# Production
vpc_cidr = "10.0.0.0/16"
control_plane_private_ip = "10.0.10.21"
worker_private_ips = ["10.0.11.30", "10.0.12.30"]

# Demo
vpc_cidr = "10.100.0.0/16"
control_plane_private_ip = "10.100.10.21"
worker_private_ips = [
  "10.100.10.30", "10.100.10.31",
  "10.100.11.30", "10.100.11.31"
]
```

### Auto Scaling
```hcl
# Production
asg_desired_capacity = 2
asg_min_size = 1
asg_max_size = 8

# Demo
asg_desired_capacity = 0  # Disabled
asg_min_size = 0
asg_max_size = 0
```

### HA Configuration
```hcl
# Production
additional_control_plane_count = 2
additional_control_plane_ips = ["10.0.11.21", "10.0.12.21"]

# Demo
additional_control_plane_count = 0
additional_control_plane_ips = []
```

### Domain
```hcl
# Production
domain_name = "kubestock.dpiyumal.me"

# Demo
domain_name = "kubestock-demo.dpiyumal.me"
```

## Files Modified

### Created/Modified in Demo
1. ✅ `backend.tf` - Removed S3 backend
2. ✅ `main.tf` - ECR disabled, static workers, ALB config
3. ✅ `variables.tf` - VPC CIDRs, IPs, counts
4. ✅ `modules/compute/dev_server_user_data.sh` - Git clone added
5. ✅ `terraform.tfvars.template` - Demo-specific template
6. ✅ `README.md` - Complete documentation
7. ✅ `QUICKSTART.md` - Fast deployment guide
8. ✅ `SETUP_COMPLETE.md` - Summary

### Ansible Inventory
1. ✅ `kubespray-inventory-demo/inventory/kubestock/hosts.ini`
2. ✅ `kubespray-inventory-demo/inventory/kubestock/inventory.ini`

## Cost Comparison (Estimated Monthly)

| Component | Production | Demo | Savings |
|-----------|-----------|------|---------|
| **EC2 - Control Plane** | 3 × t3.medium | 1 × t3.medium | ~$60/mo |
| **EC2 - Workers** | ASG (dynamic) | 4 × t3.medium | $0 (same avg) |
| **NAT Gateway** | 1 × NAT | 1 × NAT | $0 |
| **RDS** | Multi-AZ option | Single-AZ | Depends on config |
| **ECR** | Dedicated | Shared | ~$5/mo |
| **Total Savings** | - | - | **~$65/mo** |

**Demo Tip:** Destroy when not in use for maximum savings!

## Command Differences

### Terraform
```bash
# Production
terraform init  # Uses S3 backend
cd ../prod/

# Demo
terraform init  # Uses local backend
cd ../demo/
```

### Ansible
```bash
# Production
ansible-playbook -i ../../kubespray-inventory/inventory/kubestock/hosts.ini ...

# Demo
ansible-playbook -i ../../kubespray-inventory-demo/inventory/kubestock/hosts.ini ...
```

## State Management

| Aspect | Production | Demo |
|--------|-----------|------|
| **Backend** | S3 bucket | Local file |
| **State Lock** | DynamoDB | None |
| **Team Access** | Yes (S3) | No (local only) |
| **Backup** | S3 versioning | Manual |

## Security Considerations

Both environments:
- ✅ Use same security group rules
- ✅ Require IP whitelisting
- ✅ Use same SSH key authentication
- ✅ Have isolated network boundaries
- ✅ Use IAM roles for service access

Differences:
- Demo IAM roles have `-demo` suffix (no conflicts)
- Demo uses local state (keep `terraform.tfvars` secure!)

## When to Use Each

### Use Production for:
- ✅ Actual application deployment
- ✅ Customer-facing services
- ✅ CI/CD pipelines
- ✅ Long-term stable environment

### Use Demo for:
- ✅ Cluster recreation demonstrations
- ✅ Testing infrastructure changes
- ✅ Training and education
- ✅ Disaster recovery practice
- ✅ Architecture presentations
- ✅ Short-term testing (destroy after)

---

## Quick Reference

**Deploy Demo:**
```bash
cd infrastructure/terraform/demo
terraform apply
```

**Deploy Production:**
```bash
cd infrastructure/terraform/prod
terraform apply
```

**Ansible Demo:**
```bash
ansible-playbook -i ../../kubespray-inventory-demo/inventory/kubestock/hosts.ini ...
```

**Ansible Production:**
```bash
ansible-playbook -i ../../kubespray-inventory/inventory/kubestock/hosts.ini ...
```
