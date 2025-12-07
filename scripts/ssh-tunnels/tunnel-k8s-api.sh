#!/bin/bash
# ==================================================
# KubeStock SSH Tunnel to Kubernetes API (via NLB)
# ==================================================

# Path to your private key (override with KUBESTOCK_SSH_KEY env var)
KEY_PATH="${KUBESTOCK_SSH_KEY:-${HOME}/.ssh/id_ed25519}"

# Bastion host (set KUBESTOCK_BASTION_IP env var)
if [ -z "${KUBESTOCK_BASTION_IP}" ]; then
    echo "ERROR: KUBESTOCK_BASTION_IP environment variable not set"
    echo "Please set it: export KUBESTOCK_BASTION_IP=13.202.52.3"
    exit 1
fi
BASTION="ubuntu@${KUBESTOCK_BASTION_IP}"

# NLB DNS (set KUBESTOCK_NLB_DNS env var)
if [ -z "${KUBESTOCK_NLB_DNS}" ]; then
    echo "ERROR: KUBESTOCK_NLB_DNS environment variable not set"
    echo "Please set it: export KUBESTOCK_NLB_DNS=kubestock-nlb-xxx.elb.ap-south-1.amazonaws.com"
    exit 1
fi
REMOTE_API="${KUBESTOCK_NLB_DNS}"
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
