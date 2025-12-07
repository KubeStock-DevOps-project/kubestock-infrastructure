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

### 1. Set Environment Variables

All scripts use environment variables for configuration. Set these once and the scripts will work without editing.

**Linux/Mac (.sh files):**

```bash
# Get values from Terraform
cd infrastructure/terraform/prod

# Set bastion IP (REQUIRED)
export KUBESTOCK_BASTION_IP=$(terraform output -raw bastion_public_ip)

# Set NLB DNS (REQUIRED - single NLB for all services)
export KUBESTOCK_NLB_DNS=$(terraform output -raw nlb_dns_name)

# Set SSH key path (OPTIONAL - defaults to ~/.ssh/id_ed25519)
export KUBESTOCK_SSH_KEY="${HOME}/.ssh/id_ed25519"
```

To make these permanent, add to `~/.bashrc` or `~/.zshrc`:

```bash
# KubeStock Environment Variables
export KUBESTOCK_BASTION_IP="13.202.52.3"
export KUBESTOCK_NLB_DNS="kubestock-nlb-e316550036e3d7d8.elb.ap-south-1.amazonaws.com"
export KUBESTOCK_SSH_KEY="${HOME}/.ssh/id_ed25519"
```

**Windows (.bat files):**

```cmd
REM Get values from Terraform (in PowerShell)
cd infrastructure\terraform\prod
terraform output -raw bastion_public_ip
terraform output -raw nlb_dns_name

REM Set environment variables (REQUIRED)
set KUBESTOCK_BASTION_IP=13.202.52.3
set KUBESTOCK_NLB_DNS=kubestock-nlb-e316550036e3d7d8.elb.ap-south-1.amazonaws.com

REM Set SSH key path (OPTIONAL - defaults to %USERPROFILE%\.ssh\id_ed25519)
set KUBESTOCK_SSH_KEY=C:\Users\%USERNAME%\.ssh\id_ed25519
```

To make these permanent, set as system environment variables:
1. Open System Properties → Environment Variables
2. Add User Variables:
   - `KUBESTOCK_BASTION_IP` = `13.202.52.3`
   - `KUBESTOCK_NLB_DNS` = `kubestock-nlb-xxx.elb.ap-south-1.amazonaws.com`
   - `KUBESTOCK_SSH_KEY` = `C:\Users\YourName\.ssh\id_ed25519` (optional)

### 2. Make Scripts Executable (Linux/Mac)

```bash
chmod +x infrastructure/scripts/ssh-tunnels/tunnel-*.sh
```


## Usage Examples

Once environment variables are set, simply run the scripts - no editing required!

### Windows

```cmd
REM Start ArgoCD tunnel
tunnel-argocd.bat

REM Start staging frontend tunnel (HTTP)
tunnel-staging-frontend.bat

REM Start staging frontend tunnel (HTTPS)
tunnel-staging-frontend-https.bat

REM Start K8s API tunnel
tunnel-k8s-api.bat
```

If environment variables are not set, scripts will show helpful error messages:
```cmd
ERROR: KUBESTOCK_BASTION_IP environment variable not set
Please set it: set KUBESTOCK_BASTION_IP=13.202.52.3
```

### Linux/Mac

```bash
# Start ArgoCD tunnel
./tunnel-argocd.sh

# Start staging frontend tunnel (HTTP)
./tunnel-staging-frontend.sh

# Start staging frontend tunnel (HTTPS)
./tunnel-staging-frontend-https.sh

# Start K8s API tunnel
./tunnel-k8s-api.sh
```

If environment variables are not set, scripts will show helpful error messages:
```bash
ERROR: KUBESTOCK_BASTION_IP environment variable not set
Please set it: export KUBESTOCK_BASTION_IP=13.202.52.3
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
- Check bastion IP is correct: `echo $KUBESTOCK_BASTION_IP` (Linux/Mac) or `echo %KUBESTOCK_BASTION_IP%` (Windows)
- Verify NLB DNS is correct: `echo $KUBESTOCK_NLB_DNS` (Linux/Mac) or `echo %KUBESTOCK_NLB_DNS%` (Windows)
- Ensure security groups allow traffic from bastion to NLB

### SSH Permission Denied
- Check key path is correct: `echo $KUBESTOCK_SSH_KEY` (Linux/Mac) or `echo %KUBESTOCK_SSH_KEY%` (Windows)
- Verify key permissions: `chmod 600 ~/.ssh/id_ed25519` (Linux/Mac)
- Ensure key exists: `ls -la ~/.ssh/id_ed25519` (Linux/Mac)

### Environment Variables Not Set
If you see errors like "KUBESTOCK_BASTION_IP environment variable not set":

**Linux/Mac:**
```bash
# Quick setup (current shell only)
export KUBESTOCK_BASTION_IP=$(cd infrastructure/terraform/prod && terraform output -raw bastion_public_ip)
export KUBESTOCK_NLB_DNS=$(cd infrastructure/terraform/prod && terraform output -raw nlb_dns_name)

# Verify
echo "Bastion: $KUBESTOCK_BASTION_IP"
echo "NLB DNS: $KUBESTOCK_NLB_DNS"
```

**Windows:**
```cmd
REM Get values from Terraform
cd infrastructure\terraform\prod
terraform output -raw bastion_public_ip
terraform output -raw nlb_dns_name

REM Set for current session
set KUBESTOCK_BASTION_IP=<paste_bastion_ip>
set KUBESTOCK_NLB_DNS=<paste_nlb_dns>

REM Verify
echo %KUBESTOCK_BASTION_IP%
echo %KUBESTOCK_NLB_DNS%
```
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
