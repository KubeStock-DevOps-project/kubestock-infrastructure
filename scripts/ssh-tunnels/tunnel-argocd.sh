#!/bin/bash
# ==================================================
# KubeStock SSH Tunnel to ArgoCD UI (via NLB)
# ==================================================

# Path to your private key
KEY_PATH="${HOME}/.ssh/kubestock-key"

# Bastion host (replace with your bastion IP)
BASTION="ubuntu@<BASTION_IP>"

# Get NLB DNS from Terraform output first:
#   cd infrastructure/terraform/prod
#   terraform output -raw nlb_staging_dns_name
REMOTE_NLB="<NLB_STAGING_DNS>"
REMOTE_PORT=8443

# Local port
LOCAL_PORT=8443

echo "========================================"
echo "KubeStock ArgoCD UI Tunnel"
echo "========================================"
echo "Bastion:      ${BASTION}"
echo "Remote:       ${REMOTE_NLB}:${REMOTE_PORT}"
echo "Local:        https://localhost:${LOCAL_PORT}"
echo "========================================"
echo ""
echo "ArgoCD Credentials:"
echo "  Username: admin"
echo "  Password: (get from: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d)"
echo ""
echo "Starting SSH tunnel..."
echo "Press Ctrl+C to stop"
echo ""

# Start SSH tunnel (keep it running)
ssh -i "${KEY_PATH}" -L ${LOCAL_PORT}:${REMOTE_NLB}:${REMOTE_PORT} ${BASTION} -N
