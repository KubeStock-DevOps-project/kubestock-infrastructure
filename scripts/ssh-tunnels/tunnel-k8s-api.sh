#!/bin/bash
# ==================================================
# KubeStock SSH Tunnel to Kubernetes API (via NLB)
# ==================================================

# Path to your private key
KEY_PATH="${HOME}/.ssh/kubestock-key"

# Bastion host (replace with your bastion IP)
BASTION="ubuntu@<BASTION_IP>"

# Get NLB DNS from Terraform output first:
#   cd infrastructure/terraform/prod
#   terraform output -raw nlb_dns_name
REMOTE_API="<NLB_API_DNS>"
REMOTE_PORT=6443

# Local port
LOCAL_PORT=6443

echo "========================================"
echo "KubeStock Kubernetes API Tunnel"
echo "========================================"
echo "Bastion:      ${BASTION}"
echo "Remote:       ${REMOTE_API}:${REMOTE_PORT}"
echo "Local:        localhost:${LOCAL_PORT}"
echo "========================================"
echo ""
echo "Starting SSH tunnel..."
echo "Press Ctrl+C to stop"
echo ""

# Start SSH tunnel (keep it running)
ssh -i "${KEY_PATH}" -L ${LOCAL_PORT}:${REMOTE_API}:${REMOTE_PORT} ${BASTION} -N
