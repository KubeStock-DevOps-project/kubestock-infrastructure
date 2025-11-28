# Kubestock Worker AMI Scripts

Scripts for building and managing Kubernetes worker node golden AMIs.

## Files

| File | Description |
|------|-------------|
| `configure-kubelet.sh` | Configures kubelet with EC2 instance metadata (IP, hostname) |
| `join-cluster.sh` | Orchestrates the cluster join process |
| `start-nginx-proxy.sh` | Starts nginx proxy container for API server access |
| `nginx.conf` | Nginx configuration for proxying to control plane |
| `nginx-proxy.service` | Systemd service unit for nginx proxy |
| `prepare-ami.sh` | Prepares a node for AMI creation |

## Installation Locations

When installed on worker nodes:

```
/usr/local/bin/
├── configure-kubelet.sh
├── join-cluster.sh
└── start-nginx-proxy.sh

/etc/nginx/
└── nginx.conf

/etc/systemd/system/
└── nginx-proxy.service
```

## Usage

### Manual Join (for testing)

```bash
# Get join token from control plane
TOKEN=$(ssh ubuntu@<control-plane-ip> "sudo kubeadm token create")

# Join with arguments
sudo /usr/local/bin/join-cluster.sh \
  --token "$TOKEN" \
  --ca-cert-hash "sha256:<hash>"
```

### ASG with SSM (automated)

Prerequisites in SSM Parameter Store:
- `/kubestock/k8s/join-token` - Current join token
- `/kubestock/k8s/ca-cert-hash` - CA certificate hash

```bash
# User-data script
#!/bin/bash
/usr/local/bin/join-cluster.sh --ssm
```

### Building a New AMI

1. Provision a worker node with Ansible/Kubespray
2. Verify node joined successfully
3. Run the prepare script:
   ```bash
   sudo /path/to/prepare-ami.sh
   ```
4. Create AMI from the instance

See [Golden AMI Build Guide](../docs/golden-ami-build-guide.md) for details.

## Current AMI

| Property | Value |
|----------|-------|
| AMI ID | `ami-0add7db38ab766c87` |
| Name | `kubestock-worker-golden-ami-v3-20251128-141559` |
| K8s Version | v1.34.1 |
| containerd | 2.1.4 |
| CNI | Calico |

## Notes

- Scripts require IMDSv2 for EC2 metadata access
- `jq` and `awscli` must be pre-installed for SSM support
- Nginx proxy binds to `127.0.0.1:6443` and forwards to control plane
