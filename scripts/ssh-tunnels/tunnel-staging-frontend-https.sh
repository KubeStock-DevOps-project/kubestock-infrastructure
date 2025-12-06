#!/bin/bash
# ==================================================
# KubeStock SSH Tunnel to Staging Frontend HTTPS (via NLB)
# ==================================================

# Path to your private key
KEY_PATH="${HOME}/.ssh/kubestock-key"

# Bastion host (replace with your bastion IP)
BASTION="ubuntu@<BASTION_IP>"

# Get NLB DNS from Terraform output first:
#   cd infrastructure/terraform/prod
#   terraform output -raw nlb_staging_dns_name
REMOTE_NLB="<NLB_STAGING_DNS>"
REMOTE_PORT=443

# Local port
LOCAL_PORT=5173

echo "========================================"
echo "KubeStock Staging Frontend Tunnel (HTTPS)"
echo "========================================"
echo "Bastion:      ${BASTION}"
echo "Remote:       ${REMOTE_NLB}:${REMOTE_PORT}"
echo "Local:        https://localhost:${LOCAL_PORT}"
echo "========================================"
echo ""
echo "Note: You may need to accept a self-signed certificate warning"
echo ""
echo "Starting SSH tunnel..."
echo "Press Ctrl+C to stop"
echo ""

# Start SSH tunnel (keep it running)
ssh -i "${KEY_PATH}" -L ${LOCAL_PORT}:${REMOTE_NLB}:${REMOTE_PORT} ${BASTION} -N
