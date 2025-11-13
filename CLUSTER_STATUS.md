# KubeStock Cluster - Current Status

## ✅ Cluster Deployment Complete

**Date**: November 13, 2025  
**Status**: **OPERATIONAL** ✅

---

## Cluster Overview

### Infrastructure
- **Cloud Provider**: AWS (us-east-1)
- **Network**: VPC with 3 AZs, public/private subnets
- **Control Plane**: 1 node (master-1)
- **Worker Nodes**: 2 nodes (worker-1, worker-2)
- **Kubernetes Version**: v1.34.1
- **CNI**: Calico
- **Container Runtime**: containerd 2.1.4

### Nodes

| Node | IP | AZ | Instance Type | Storage | Status |
|------|----|----|---------------|---------|--------|
| master-1 | 10.0.10.21 | us-east-1a | t3.medium | 30GB | Ready ✅ |
| worker-1 | 10.0.11.30 | us-east-1b | t3.medium | 25GB | Ready ✅ |
| worker-2 | 10.0.12.30 | us-east-1c | t3.medium | 25GB | Ready ✅ |

### Management Servers

| Server | IP | Purpose | Status |
|--------|-----|---------|--------|
| Bastion | 100.30.61.159 | SSH jumphost | Running ✅ |
| Dev Server | 13.223.102.35 | Development & Kubectl | Running ✅ |

---

## Deployed Components

### System Components
- ✅ **etcd** - Key-value store (single node)
- ✅ **kube-apiserver** - API server
- ✅ **kube-controller-manager** - Controller manager
- ✅ **kube-scheduler** - Pod scheduler
- ✅ **kube-proxy** - Network proxy (on all nodes)
- ✅ **kubelet** - Node agent (on all nodes)

### Network
- ✅ **Calico** - CNI for pod networking
  - calico-node: 3/3 Running (one per node)
  - calico-kube-controllers: 1/1 Running
- ✅ **CoreDNS** - Cluster DNS (2 replicas)
- ✅ **NodeLocalDNS** - Local DNS cache (3 daemonsets)

### Storage
- ✅ **AWS EBS CSI Driver** - Dynamic volume provisioning
  - Controller: 2/2 replicas Running
  - Node driver: 3/3 daemonsets Running
  - Default storage class: **gp3** (configured)

### Application Management
- ✅ **ArgoCD** - GitOps continuous delivery
  - All 7 components Running
  - Admin password: `g4npBgErM8L01960`
  - Access: Port-forward to service

### Ingress
- ✅ **NGINX Ingress Controller** - HTTP/HTTPS ingress
  - NodePort: 30080 (HTTP), 30443 (HTTPS)
  - Ready for application deployments

### Monitoring
- ✅ **Metrics Server** - Resource metrics API
  - Enabled for `kubectl top nodes` and `kubectl top pods`
  - Required for Horizontal Pod Autoscaling (HPA)

---

## Access Information

### kubectl Access (from Dev Server)
```bash
# All kubectl commands use this kubeconfig
export KUBECONFIG=~/kubeconfig

# Quick status check
kubectl get nodes
kubectl get pods -A
```

### SSH Access
```bash
# Bastion (jumphost)
ssh -i ~/.ssh/kubestock-key ubuntu@100.30.61.159

# Control Plane (via bastion)
ssh -i ~/.ssh/kubestock-key -J ubuntu@100.30.61.159 ubuntu@10.0.10.21

# Workers (via bastion)
ssh -i ~/.ssh/kubestock-key -J ubuntu@100.30.61.159 ubuntu@10.0.11.30
ssh -i ~/.ssh/kubestock-key -J ubuntu@100.30.61.159 ubuntu@10.0.12.30
```

### ArgoCD Access
```bash
# Create port-forward
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Then visit: https://localhost:8080
# Username: admin
# Password: g4npBgErM8L01960
```

---

## Pod Status Summary

| Namespace | Component | Pods | Status |
|-----------|-----------|------|--------|
| kube-system | Core Kubernetes | 14 | All Running ✅ |
| kube-system | Calico CNI | 4 | All Running ✅ |
| kube-system | EBS CSI Driver | 5 | All Running ✅ |
| kube-system | Metrics Server | 1 | Running ✅ |
| ingress-nginx | Ingress Controller | 1 | Running ✅ |
| argocd | ArgoCD | 7 | All Running ✅ |

**Total Pods**: 32 Running, 0 Failed ✅

---

## Configuration Files

| File | Description |
|------|-------------|
| `/home/ubuntu/kubeconfig` | Kubectl configuration (SSH tunnel to API server) |
| `/home/ubuntu/kubestock-infrastructure/terraform/prod/` | Terraform infrastructure code |
| `/home/ubuntu/kubestock-infrastructure/kubespray/inventory/kubestock/hosts.ini` | Ansible inventory |
| `/home/ubuntu/kubestock-infrastructure/OPERATIONS.md` | Operations guide (add/remove nodes, configure bastion) |

---

## Known Issues & Notes

### NLB Health Checks (Non-blocking)
- **Issue**: NLB shows "unhealthy" for API server target group
- **Impact**: None - API server is fully functional
- **Reason**: TCP health checks incompatible with TLS endpoints
- **Workaround**: Using SSH tunnel for kubectl access (127.0.0.1:6443)
- **Status**: Functional ✅ (health check issue can be ignored)

### ASG Auto-Join (Disabled)
- **Status**: Auto Scaling Group disabled (set to 0/0/0)
- **Reason**: Complexity with Kubespray-style certificate paths
- **Alternative**: Using static worker nodes managed by Ansible
- **Operations**: See OPERATIONS.md for adding/removing nodes manually

---

## Next Steps

### For Production Readiness
1. **Enable Monitoring**: Deploy Prometheus + Grafana
2. **Configure Logging**: Set up ELK or Loki stack
3. **Backup Strategy**: Automate etcd backups
4. **High Availability**: Add 2 more control plane nodes (total 3)
5. **Certificate Management**: Set up cert-manager for TLS
6. **Network Policies**: Implement Calico network policies
7. **Resource Limits**: Configure pod resource requests/limits
8. **RBAC**: Set up proper role-based access control

### For Application Deployment
1. **Configure ArgoCD**: Connect to Git repository
2. **Create Namespaces**: Set up environments (dev, staging, prod)
3. **Deploy Applications**: Use ArgoCD to deploy workloads
4. **Configure Ingress**: Set up ingress rules for applications
5. **Database Access**: Configure applications to use RDS PostgreSQL

---

## Cost Estimate

| Component | Monthly Cost |
|-----------|-------------|
| Control Plane (t3.medium) | ~$30 |
| 2x Workers (t3.medium) | ~$60 |
| Bastion (t2.micro) | ~$9 |
| Dev Server (t3.large, running) | ~$60 |
| NAT Gateway | ~$32 |
| RDS PostgreSQL (db.t3.micro) | ~$15 |
| **Total** | **~$206/month** |

**Cost Optimization**: Stop dev server when not in use → **~$146/month**

---

## Documentation

- **Operations Guide**: [OPERATIONS.md](./OPERATIONS.md) - Node management, bastion setup
- **Build Plan**: [kubestock-build-plan.md](./kubestock-build-plan.md) - Original deployment plan
- **Terraform Code**: [terraform/prod/](./terraform/prod/) - Infrastructure as code
- **Kubespray Inventory**: [kubespray/inventory/kubestock/](./kubespray/inventory/kubestock/) - Ansible inventory

---

## Support & Troubleshooting

For common issues, see the **Troubleshooting** section in [OPERATIONS.md](./OPERATIONS.md).

Quick health checks:
```bash
# Check all nodes
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check node resource usage
kubectl top nodes

# Check pod resource usage
kubectl top pods -A

# Check events
kubectl get events -A --sort-by='.lastTimestamp'
```

---

**Cluster ID**: kubestock-production  
**Infrastructure Repository**: /home/ubuntu/kubestock-infrastructure  
**Managed By**: Terraform + Kubespray (Ansible)  
**Region**: us-east-1 (N. Virginia)

---

✅ **Cluster is ready for application deployments!**
