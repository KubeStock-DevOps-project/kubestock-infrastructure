# KubeStock Cluster Operations Guide

## Table of Contents
1. [Adding Worker Nodes](#adding-worker-nodes)
2. [Removing Worker Nodes](#removing-worker-nodes)
3. [Configuring Bastion for kubectl](#configuring-bastion-for-kubectl)
4. [Cluster Information](#cluster-information)

---

## Adding Worker Nodes

### 1. Create EC2 Instance via Terraform

Edit `/home/ubuntu/kubestock-infrastructure/terraform/prod/compute.tf`:

```terraform
# Increase the count parameter
resource "aws_instance" "worker" {
  count = 3  # Change from 2 to 3 to add one more worker
  ...
  
  # Update private_ip assignment logic for additional workers
  private_ip = count.index == 0 ? "10.0.11.30" : (count.index == 1 ? "10.0.12.30" : "10.0.10.30")
  ...
}
```

Apply Terraform changes:
```bash
cd /home/ubuntu/kubestock-infrastructure/terraform/prod
terraform apply
```

Note the private IP of the new worker from Terraform output.

### 2. Update Kubespray Inventory

Edit `/home/ubuntu/kubestock-infrastructure/kubespray/inventory/kubestock/hosts.ini`:

```ini
[all]
master-1 ansible_host=10.0.10.21 ansible_user=ubuntu etcd_member_name=etcd-1
worker-1 ansible_host=10.0.11.30 ansible_user=ubuntu
worker-2 ansible_host=10.0.12.30 ansible_user=ubuntu
worker-3 ansible_host=10.0.10.30 ansible_user=ubuntu  # NEW

[kube_control_plane]
master-1

[etcd]
master-1

[kube_node]
worker-1
worker-2
worker-3  # NEW

[k8s_cluster:children]
kube_control_plane
kube_node
```

### 3. Run Kubespray Scale Playbook

```bash
cd /home/ubuntu/kubestock-infrastructure/kubespray
ansible-playbook -i inventory/kubestock/hosts.ini scale.yml -b
```

This will:
- Install Kubernetes components on new nodes
- Configure containerd, kubelet, kube-proxy
- Join nodes to the cluster
- Deploy Calico CNI on new nodes
- Deploy EBS CSI driver daemonsets
# KubeStock Operations Guide

A concise overview of the production cluster plus links to detailed runbooks.

## 📚 Quick Reference

| Topic | Location |
| --- | --- |
| Ansible / Kubespray setup & playbook usage | [`docs/ansible-getting-started.md`](docs/ansible-getting-started.md) |
| Adding/removing workers or rebuilding the control plane | [`docs/node-management.md`](docs/node-management.md) |
| Developer onboarding, tunnels, and kubectl access | [`docs/developer-access.md`](docs/developer-access.md) |

## 🛰️ Cluster Snapshot

- **Control plane**: `master-1` (`t3.medium`, private IP `10.0.10.21`, AZ `us-east-1a`).
- **Workers**: `worker-1` (`10.0.11.30`, AZ `us-east-1b`) and `worker-2` (`10.0.12.30`, AZ `us-east-1c`).
- **Networking**: VPC `10.0.0.0/16`, three public + three private subnets, single NAT (`nat-031c7ccd7503f985a`).
- **Kubernetes**: v1.34.1, containerd, Calico.
- **Add-ons**: AWS EBS CSI driver, NGINX Ingress, ArgoCD.
- **Access**: Bastion `100.30.61.159` (always on) and dev server `13.223.102.35` (start/stop to save costs).

## 🔐 Essential Commands

Terraform insights:
```bash
cd ~/kubestock-infrastructure/terraform/prod
terraform output
terraform output -raw bastion_public_ip
terraform output -raw control_plane_private_ip
terraform output -json worker_private_ips | jq -r '.[]'
```

Run Kubespray:
```bash
cd ~/kubestock-infrastructure/kubespray
source venv/bin/activate
ansible-playbook -i inventory/kubestock/hosts.ini --become --become-user=root cluster.yml
```

Check cluster health:
```bash
export KUBECONFIG=~/kubeconfig
kubectl get nodes -o wide
kubectl get pods -A
```

## 💰 Cost Tips
- Stop the dev server when idle (`aws ec2 stop-instances --instance-ids <dev-server-id>`).
- Keep static workers unless auto-scaling is revisited.
- Monitor NAT Gateway egress (most traffic flows through `us-east-1a`).

## 🧭 Next Steps
- Follow the linked docs for detailed procedures (Ansible runs, node lifecycle, developer workflows).
- Treat `terraform/prod/terraform.tfvars` as the single source of truth for `control_plane_private_ip` and `worker_private_ips`.
- After Terraform changes, rerun the appropriate Kubespray playbook so Kubernetes matches the underlying infrastructure.
  -e delete_nodes_confirmation=yes \
