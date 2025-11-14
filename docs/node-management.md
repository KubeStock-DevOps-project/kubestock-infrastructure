# Node Management Guide

This document explains how to add/remove worker nodes and how to rebuild the single control-plane node that powers Kubestock.

## Adding a worker node

1. **Choose a new IP address** inside the appropriate private subnet (`10.0.11.0/24` or `10.0.12.0/24`).
2. **Update Terraform vars** (`terraform/prod/terraform.tfvars`):
   ```hcl
   worker_private_ips = [
     "10.0.11.30",
     "10.0.12.30",
     "10.0.11.40" # new worker
   ]
   ```
3. **Deploy the instance**:
   ```bash
   cd ~/kubestock-infrastructure/terraform/prod
   terraform plan
   terraform apply
   ```
4. **Extend the Kubespray inventory** (`kubespray/inventory/kubestock/hosts.ini`):
   ```ini
   worker-3 ansible_host=10.0.11.40 ip=10.0.11.40 ansible_user=ubuntu
   ```
   Add the host under `[kube_node]` as well.
5. **Run the scale playbook**:
   ```bash
   cd ~/kubestock-infrastructure/kubespray
   source venv/bin/activate
   ansible-playbook -i inventory/kubestock/hosts.ini scale.yml -b
   ```
6. **Verify**:
   ```bash
   KUBECONFIG=~/kubeconfig kubectl get nodes -o wide
   ```

## Removing a worker node

1. **Drain & delete from Kubernetes**:
   ```bash
   KUBECONFIG=~/kubeconfig kubectl drain worker-3 --ignore-daemonsets --delete-emptydir-data
   KUBECONFIG=~/kubeconfig kubectl delete node worker-3
   ```
2. **Update Kubespray inventory** (remove the host from `[all]` and `[kube_node]`).
3. **Optional clean-up on the node**:
   ```bash
   cd ~/kubestock-infrastructure/kubespray
   source venv/bin/activate
   ansible-playbook -i inventory/kubestock/hosts.ini remove-node.yml \
     -e node=worker-3 -e delete_nodes_confirmation=yes -b
   ```
4. **Update Terraform vars** (remove the IP from `worker_private_ips`) and apply:
   ```bash
   terraform apply
   ```

## Rebuilding the control-plane node

> Kubestock currently runs a single control-plane instance. Rebuilding replaces the VM at `var.control_plane_private_ip` (default `10.0.10.21`).

1. **Optionally change the private IP** by editing `control_plane_private_ip` in `terraform/prod/terraform.tfvars`.
2. **Apply Terraform** to recreate the node:
   ```bash
   cd ~/kubestock-infrastructure/terraform/prod
   terraform plan
   terraform apply
   ```
   Terraform will destroy the old instance and create a new one at the target IP.
3. **Re-run Kubespray** to configure the new control plane:
   ```bash
   cd ~/kubestock-infrastructure/kubespray
   source venv/bin/activate
   ansible-playbook -i inventory/kubestock/hosts.ini --become --become-user=root cluster.yml --limit master-1
   ```
4. **Validate**:
   ```bash
   KUBECONFIG=~/kubeconfig kubectl get nodes -o wide
   ```

### Notes
- For multi-control-plane HA, additional Terraform and Kubespray changes are required (out of scope here).
- Whenever Terraform changes the instance list, make sure the `hosts.ini` file mirrors those IPs exactly.
