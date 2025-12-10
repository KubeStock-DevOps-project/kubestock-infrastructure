# KubeStock SSH Tunnel Scripts

This directory contains SSH tunnel scripts for accessing KubeStock services through the bastion host via the Network Load Balancer (NLB).

## Why Use the NLB?

The NLB provides:
- **Static DNS endpoint** - No need to track dynamic worker node IPs
- **High availability** - Traffic automatically routes to healthy nodes
- **Auto-scaling support** - New worker nodes automatically join target groups
- **Simplified access** - Single endpoint for all services

## Architecture

Services are accessed through the internal NLB:

```
Your Machine          Bastion Host              NLB                Worker Nodes
============          ============              ===                ============

Staging (via kong-staging namespace):
localhost:5173  →  SSH Tunnel  →  nlb:81    →  NodePort 30081 (Kong Staging HTTP)
localhost:5174  →  SSH Tunnel  →  nlb:444   →  NodePort 30445 (Kong Staging HTTPS)

Production (via kong namespace - also accessible via ALB):
localhost:8080  →  SSH Tunnel  →  nlb:80    →  NodePort 30080 (Kong Production HTTP)
localhost:8443  →  SSH Tunnel  →  nlb:443   →  NodePort 30444 (Kong Production HTTPS)

ArgoCD & Kubernetes API:
localhost:9443  →  SSH Tunnel  →  nlb:8443  →  NodePort 30443 (ArgoCD)
localhost:6443  →  SSH Tunnel  →  nlb:6443  →  Control Plane 6443

Observability Stack (shared by staging & production):
localhost:3000  →  SSH Tunnel  →  nlb:3000  →  NodePort 30300 (Grafana)
localhost:9090  →  SSH Tunnel  →  nlb:9090  →  NodePort 30090 (Prometheus)
localhost:9093  →  SSH Tunnel  →  nlb:9093  →  NodePort 30093 (Alertmanager - prod only)
```

**Production is also accessible via ALB at: https://kubestock.dpiyumal.me**

## Available Scripts

### Unified "All Tunnels" Scripts (Recommended)

- `tunnel-all.sh` (Linux/Mac)
- `tunnel-all.bat` (Windows)

These scripts open **all common tunnels at once** in a single SSH session:

| Purpose                  | Local Endpoint             | NLB Port |
|--------------------------|---------------------------|----------|
| Staging Frontend (HTTP)  | `http://localhost:5173`   | `80`     |
| Staging Frontend (HTTPS) | `https://localhost:5174`  | `443`    |
| Kubernetes API           | `https://localhost:6443`  | `6443`   |
| ArgoCD UI                | `https://localhost:8443`  | `8443`   |
| Grafana                  | `http://localhost:3000`   | `3000`   |
| Prometheus               | `http://localhost:9090`   | `9090`   |
| Alertmanager (prod only) | `http://localhost:9093`   | `9093`   |

> The previous per-service scripts (e.g. `tunnel-grafana.sh`, `tunnel-prometheus.sh`,
> `tunnel-k8s-api.sh`, etc.) have been consolidated into these two unified scripts
> to keep usage simple and consistent.

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
REM Start ALL tunnels (staging, API, ArgoCD, observability)
tunnel-all.bat
```

If environment variables are not set, scripts will show helpful error messages:
```cmd
ERROR: KUBESTOCK_BASTION_IP environment variable not set
Please set it: set KUBESTOCK_BASTION_IP=13.202.52.3
```

### Linux/Mac

```bash
# Start ALL tunnels (staging, API, ArgoCD, observability)
./tunnel-all.sh
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
| 3000 | 3000 | 30300 | Grafana (Dashboards & Logs) |
| 9090 | 9090 | 30090 | Prometheus (Metrics) |
| 9093 | 9093 | 30093 | Alertmanager (Alerts - prod only) |

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
