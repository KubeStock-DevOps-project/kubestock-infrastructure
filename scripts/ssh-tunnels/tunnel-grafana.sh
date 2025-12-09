#!/bin/bash
# ==================================================
# KubeStock SSH Tunnel to Grafana UI (via NLB)
# ==================================================
# Access Grafana dashboards for metrics visualization and logs
# Grafana serves as the unified UI for Prometheus metrics and Loki logs

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
REMOTE_NLB="${KUBESTOCK_NLB_DNS}"
REMOTE_PORT=3000

# Local port
LOCAL_PORT=3000

echo "========================================"
echo "KubeStock Grafana UI Tunnel"
echo "========================================"
echo "Bastion:      ${BASTION}"
echo "Remote:       ${REMOTE_NLB}:${REMOTE_PORT}"
echo "Local:        http://localhost:${LOCAL_PORT}"
echo "========================================"
echo ""
echo "Grafana Credentials:"
echo "  Username: admin"
echo "  Password: admin (change on first login)"
echo ""
echo "Available Datasources:"
echo "  - Prometheus (metrics)"
echo "  - Loki (logs)"
echo ""
echo "Starting SSH tunnel..."
echo "Press Ctrl+C to stop"
echo ""

# Start SSH tunnel (keep it running)
ssh -i "${KEY_PATH}" -L ${LOCAL_PORT}:${REMOTE_NLB}:${REMOTE_PORT} ${BASTION} -N
