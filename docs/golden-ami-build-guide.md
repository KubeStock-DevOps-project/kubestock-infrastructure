# Kubestock Worker Node Golden AMI Build Guide

## Overview

This guide documents how to build a golden AMI for Kubernetes worker nodes that can be used with Auto Scaling Groups (ASG). The AMI contains all necessary components pre-installed and configured, allowing new nodes to join the cluster with a simple `kubeadm join` command.

## Prerequisites

- Access to the kubestock-infrastructure repository
- SSH access to the dev server and cluster nodes
- AWS CLI configured with appropriate permissions
- Ansible venv activated in kubespray directory

## What's Included in the Golden AMI

- **Container Runtime**: containerd v2.1.4
- **Kubernetes Components**: 
  - kubelet v1.34.1
  - kubeadm v1.34.1
- **CNI**: Calico with calicoctl
- **Networking**: nginx-proxy for API server access
- **Helper Scripts**:
  - `/usr/local/bin/configure-kubelet.sh` - Configures kubelet with dynamic IP/hostname
  - `/usr/local/bin/join-cluster.sh` - Joins node to cluster (supports SSM)
  - `/usr/local/bin/start-nginx-proxy.sh` - Starts nginx proxy container

## Build Process

### Step 1: Provision Base Instance

The golden AMI builder instance is defined in Terraform:

```hcl
# terraform/prod/compute.tf
resource "aws_instance" "worker-golden-ami-builder" {
  ami           = data.aws_ami.ubuntu.id  # Ubuntu 22.04
  instance_type = var.worker_instance_type
  private_ip    = "10.0.11.50"
  # ... other config
}
```

### Step 2: Run Ansible Scale Playbook

Configure the node with all K8s components using Kubespray:

```bash
cd /home/ubuntu/kubestock-infrastructure/kubespray
source venv/bin/activate

# Gather facts first
ansible-playbook -i inventory/kubestock/hosts.ini \
  playbooks/facts.yml \
  --become --become-user=root

# Scale to configure the worker node
ansible-playbook -i inventory/kubestock/hosts.ini \
  --become --become-user=root \
  --limit worker-3 \
  scale.yml
```

This installs and configures:
- containerd
- kubelet & kubeadm
- Calico CNI plugins
- nginx-proxy for API server access
- All required kernel modules and sysctl settings

### Step 3: Verify Node Joined

```bash
kubectl get nodes
# Should show worker-3 in Ready state
```

### Step 4: Drain and Reset Node

```bash
# Drain the node
kubectl drain worker-3 --ignore-daemonsets --delete-emptydir-data --force
kubectl delete node worker-3

# SSH to the worker and reset
ssh -i ~/.ssh/kubestock-key ubuntu@10.0.11.50

# On worker:
sudo systemctl stop kubelet
sudo kubeadm reset -f

# Clean node-specific files
sudo rm -rf /var/lib/kubelet/pki/* \
            /var/lib/cni/* \
            /etc/cni/net.d/* \
            /var/lib/calico/* 2>/dev/null
sudo rm -f /etc/kubernetes/kubeadm-client.conf
```

### Step 5: Restore Essential Files

These files must be present for nodes to join:

```bash
# Restore CA certificate (from control plane)
ssh ubuntu@10.0.10.21 "sudo cat /etc/kubernetes/pki/ca.crt" | \
  ssh ubuntu@10.0.11.50 "sudo tee /etc/kubernetes/ssl/ca.crt > /dev/null"

# Restore nginx-proxy manifest (from existing worker)
ssh ubuntu@10.0.11.30 "sudo cat /etc/kubernetes/manifests/nginx-proxy.yml" | \
  ssh ubuntu@10.0.11.50 "sudo tee /etc/kubernetes/manifests/nginx-proxy.yml > /dev/null"
```

### Step 6: Create Helper Scripts

The following scripts enable dynamic node configuration:

#### configure-kubelet.sh
Located at `/usr/local/bin/configure-kubelet.sh`:
- Fetches instance IP and ID from EC2 metadata
- Updates `/etc/kubernetes/kubelet.env` with correct node-ip and hostname
- Updates `/etc/kubernetes/kubelet-config.yaml` with correct address

#### join-cluster.sh
Located at `/usr/local/bin/join-cluster.sh`:
- Configures kubelet dynamically
- Fetches join token from SSM Parameter Store (or accepts as args)
- Waits for nginx-proxy to be ready
- Executes `kubeadm join`

#### start-nginx-proxy.sh
Located at `/usr/local/bin/start-nginx-proxy.sh`:
- Starts nginx-proxy container using nerdctl
- Waits for proxy to be ready

### Step 7: Enable nginx-proxy Service

```bash
# Create and enable systemd service
sudo systemctl daemon-reload
sudo systemctl enable nginx-proxy.service
```

### Step 8: Create AMI

```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=private-ip-address,Values=10.0.11.50" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Create AMI (no-reboot to avoid downtime)
aws ec2 create-image \
  --instance-id "$INSTANCE_ID" \
  --name "kubestock-worker-golden-ami-$(date +%Y%m%d-%H%M%S)" \
  --description "Kubestock K8s worker node golden AMI" \
  --no-reboot
```

### Step 9: Wait for AMI

```bash
aws ec2 describe-images --image-ids <ami-id> \
  --query 'Images[0].State'
# Wait until "available"
```

## Testing the AMI

### Manual Join Test

1. Launch a new instance from the AMI
2. SSH to the instance
3. Run the join script:

```bash
# Get join token from control plane
JOIN_TOKEN=$(ssh ubuntu@10.0.10.21 "sudo kubeadm token create")
CERT_HASH="eeb5ebf75506025f4337442b4ad2178dbce8038d0613414e39812cdf825bcb2e"

# Join the cluster
sudo /usr/local/bin/join-cluster.sh "$JOIN_TOKEN" "$CERT_HASH"
```

4. Verify on control plane:
```bash
kubectl get nodes
```

## Current AMI Information

| Property | Value |
|----------|-------|
| AMI ID | `ami-09d8ae7c9b76bc3ee` |
| Name | `kubestock-worker-golden-ami-20251126-200458` |
| K8s Version | v1.34.1 |
| Container Runtime | containerd 2.1.4 |
| CNI | Calico |
| Base OS | Ubuntu 22.04 LTS |

## Files in the AMI

```
/etc/kubernetes/
├── kubelet-config.yaml    # Kubelet configuration
├── kubelet.env            # Kubelet environment (dynamic)
├── manifests/
│   └── nginx-proxy.yml    # Static pod for nginx proxy
├── pki -> /etc/kubernetes/ssl
└── ssl/
    └── ca.crt             # Cluster CA certificate

/etc/nginx/
└── nginx.conf             # Nginx proxy config (points to control plane)

/usr/local/bin/
├── calicoctl.sh           # Calico CLI wrapper
├── configure-kubelet.sh   # Dynamic kubelet configuration
├── join-cluster.sh        # Cluster join script
└── start-nginx-proxy.sh   # Nginx proxy startup

/etc/systemd/system/
└── nginx-proxy.service    # Systemd service for nginx proxy
```

## Troubleshooting

### Node fails to join
1. Check nginx-proxy is running: `nerdctl ps | grep nginx-proxy`
2. Test API connectivity: `curl -sk https://127.0.0.1:6443/version`
3. Check join logs: `cat /var/log/k8s-join.log`

### API server unreachable
1. Verify nginx.conf points to correct control plane IP
2. Check security groups allow traffic on port 6443
3. Restart nginx-proxy: `nerdctl restart nginx-proxy`

### Token expired
Tokens expire after 24 hours. Create a new one:
```bash
ssh ubuntu@10.0.10.21 "sudo kubeadm token create"
```

## When to Rebuild the AMI

Rebuild the AMI when:
- Kubernetes version is upgraded
- containerd is upgraded
- Calico is upgraded
- kubelet configuration changes
- New kernel modules or sysctl settings are required
