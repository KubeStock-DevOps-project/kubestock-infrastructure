# KubeStock SSH Tunnel Scripts

This directory contains SSH tunnel scripts for accessing KubeStock services through the bastion host via the Network Load Balancer (NLB).

## Why Use the NLB?

The NLB provides:
- **Static DNS endpoint** - No need to track dynamic worker node IPs
- **High availability** - Traffic automatically routes to healthy nodes
- **Auto-scaling support** - New worker nodes automatically join target groups
- **Simplified access** - Single endpoint for all services

## Architecture

All services are accessed through a single internal NLB:

```
Your Machine          Bastion Host              NLB                Worker Nodes
============          ============              ===                ============

localhost:5173  →  SSH Tunnel  →  nlb:80    →  NodePort 30080 (Kong HTTP)
localhost:5173  →  SSH Tunnel  →  nlb:443   →  NodePort 30444 (Kong HTTPS)
localhost:8443  →  SSH Tunnel  →  nlb:8443  →  NodePort 30443 (ArgoCD)
localhost:6443  →  SSH Tunnel  →  nlb:6443  →  Control Plane 6443
```

## Available Scripts

### Kubernetes API Access
- `tunnel-k8s-api.bat` / `tunnel-k8s-api.sh`
  - Tunnels kubectl access to K8s API server
  - Local: `localhost:6443` → NLB → Control Plane `:6443`

### ArgoCD UI Access
- `tunnel-argocd.bat` / `tunnel-argocd.sh`
  - Tunnels web browser to ArgoCD UI
  - Local: `https://localhost:8443` → NLB `:8443` → Worker NodePort `:30443`
  - Default credentials: `admin` / (get from secret)

### Staging Frontend Access
- `tunnel-staging-frontend.bat` / `tunnel-staging-frontend.sh`
  - HTTP access to staging frontend
  - Local: `http://localhost:5173` → NLB `:80` → Kong Gateway NodePort `:30080`

- `tunnel-staging-frontend-https.bat` / `tunnel-staging-frontend-https.sh`
  - HTTPS access to staging frontend
  - Local: `https://localhost:5173` → NLB `:443` → Kong Gateway NodePort `:30444`

## Setup Instructions

### 1. Get NLB DNS and Bastion IP

From the Terraform directory:

```bash
cd infrastructure/terraform/prod

# Get NLB DNS (single NLB for all services)
terraform output -raw nlb_dns_name

# Get bastion public IP
terraform output -raw bastion_public_ip
```

### 2. Configure Scripts

Edit each script and replace:
- `<BASTION_IP>` with your bastion public IP
- `<NLB_API_DNS>` with NLB DNS (for k8s-api tunnel)
- `<NLB_STAGING_DNS>` with NLB DNS (for argocd and frontend tunnels)

**Note:** Since we use a single NLB, `<NLB_API_DNS>` and `<NLB_STAGING_DNS>` will be the same value.

### 3. Set Key Path

**Windows (.bat files):**
- Default: `C:\Users\%USERNAME%\.ssh\kubestock-key`
- Update `KEY_PATH` variable if your key is elsewhere

**Linux/Mac (.sh files):**
- Default: `${HOME}/.ssh/kubestock-key`
- Update `KEY_PATH` variable if your key is elsewhere
- Make script executable: `chmod +x tunnel-*.sh`

## Usage Examples

### Windows

```cmd
REM Start ArgoCD tunnel
tunnel-argocd.bat

REM Start staging frontend tunnel
tunnel-staging-frontend.bat

REM Start K8s API tunnel
tunnel-k8s-api.bat
```

### Linux/Mac

```bash
# Start ArgoCD tunnel
./tunnel-argocd.sh

# Start staging frontend tunnel
./tunnel-staging-frontend.sh

# Start K8s API tunnel
./tunnel-k8s-api.sh
```

## Architecture

```
Your Machine                  Bastion Host                    NLB                         Worker Nodes
============                  ============                    ===                         ============

localhost:5173  ──SSH──> ubuntu@<BASTION> ──Forward──> <NLB_DNS>:80  ──Route──> NodePort 30080 (Kong)
localhost:8443  ──SSH──> ubuntu@<BASTION> ──Forward──> <NLB_DNS>:8443 ──Route──> NodePort 30443 (ArgoCD)
localhost:6443  ──SSH──> ubuntu@<BASTION> ──Forward──> <NLB_API>:6443 ──Route──> Control Plane 6443
```

## NLB Port Mappings

All services use a single internal NLB with multiple listeners:

| Local Port | NLB Port | Target Port | Service |
|------------|----------|-------------|---------|
| 5173 | 80 | 30080 | Kong Gateway (HTTP) |
| 5173 | 443 | 30444 | Kong Gateway (HTTPS) |
| 8443 | 8443 | 30443 | ArgoCD UI |
| 6443 | 6443 | 6443 | Kubernetes API Server |

## Troubleshooting

### Connection Refused
- Check bastion IP is correct
- Verify NLB DNS is correct
- Ensure security groups allow traffic from bastion to NLB

### SSH Permission Denied
- Check key path is correct
- Verify key permissions: `chmod 600 ~/.ssh/kubestock-key` (Linux/Mac)
- Ensure bastion has your public key in `~/.ssh/authorized_keys`

### Tunnel Works but Service Unreachable
- Check NLB target group health in AWS console
- Verify worker nodes are registered with NLB
- Check NodePort services are running: `kubectl get svc -A | grep NodePort`

### Get NLB Health Status

```bash
# From bastion
kubectl get nodes -o wide

# Check target group health in AWS Console:
# EC2 → Load Balancers → Select NLB → Target Groups
```

## Security Notes

- All tunnels route through the bastion host (jump server)
- Bastion is the only instance with public IP
- NLB is internal (private subnet only)
- Security groups restrict access to bastion and dev server only
- All traffic is encrypted via SSH tunnel
