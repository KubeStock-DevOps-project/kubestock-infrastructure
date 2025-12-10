#!/bin/bash
# ==================================================
# KubeStock - Start ALL SSH Tunnels (Linux/Mac)
# ==================================================
# This script opens SSH tunnels for all commonly used
# KubeStock endpoints in a single SSH session:
#
# - Staging Frontend (HTTP):   http://localhost:5173
# - Staging Frontend (HTTPS):  https://localhost:5174
# - Kubernetes API:            https://localhost:6443
# - ArgoCD UI:                 https://localhost:8443
# - Grafana (prod):            http://localhost:3000
# - Grafana (staging):         http://localhost:3001
# - Prometheus (prod):         http://localhost:9090
# - Prometheus (staging):      http://localhost:9091
# - Alertmanager (prod only):  http://localhost:9093
#
# It relies on the same environment variables as the
# previous per-service scripts:
#   KUBESTOCK_BASTION_IP  - bastion public IP
#   KUBESTOCK_NLB_DNS     - internal NLB DNS name
#   KUBESTOCK_SSH_KEY     - path to SSH private key (optional)

set -euo pipefail

# Resolve SSH key path (allows override via env var)
KEY_PATH="${KUBESTOCK_SSH_KEY:-${HOME}/.ssh/id_ed25519}"

# Validate bastion host configuration
if [ -z "${KUBESTOCK_BASTION_IP:-}" ]; then
    echo "ERROR: KUBESTOCK_BASTION_IP environment variable not set"
    echo "Please set it, for example:"
    echo "  export KUBESTOCK_BASTION_IP=13.202.52.3"
    exit 1
fi
BASTION="ubuntu@${KUBESTOCK_BASTION_IP}"

# Validate NLB DNS configuration
if [ -z "${KUBESTOCK_NLB_DNS:-}" ]; then
    echo "ERROR: KUBESTOCK_NLB_DNS environment variable not set"
    echo "Please set it, for example:"
    echo "  export KUBESTOCK_NLB_DNS=kubestock-nlb-xxx.elb.ap-south-1.amazonaws.com"
    exit 1
fi
REMOTE_NLB="${KUBESTOCK_NLB_DNS}"

echo "========================================"
echo "KubeStock - ALL Tunnels"
echo "========================================"
echo "Bastion: ${BASTION}"
echo "NLB:     ${REMOTE_NLB}"
echo "SSH key: ${KEY_PATH}"
echo "----------------------------------------"
echo "Local endpoints that will be available:"
echo "  Staging HTTP:        http://localhost:5173  -> NLB:80"
echo "  Staging HTTPS:       https://localhost:5174 -> NLB:443"
echo "  Kubernetes API:      https://localhost:6443 -> NLB:6443"
echo "  ArgoCD UI:           https://localhost:8443 -> NLB:8443"
echo "  Grafana (prod):      http://localhost:3000  -> NLB:3000"
echo "  Grafana (staging):   http://localhost:3001  -> NLB:3001"
echo "  Prometheus (prod):   http://localhost:9090  -> NLB:9090"
echo "  Prometheus (staging):http://localhost:9091  -> NLB:9091"
echo "  Alertmanager (prod): http://localhost:9093  -> NLB:9093"
echo "========================================"
echo "Press Ctrl+C to close ALL tunnels."
echo ""

# Single SSH session with multiple local forwards.
# This keeps things simple and ensures all tunnels
# start and stop together.
ssh -i "${KEY_PATH}" \
  -L 5173:"${REMOTE_NLB}":80 \
  -L 5174:"${REMOTE_NLB}":443 \
  -L 6443:"${REMOTE_NLB}":6443 \
  -L 8443:"${REMOTE_NLB}":8443 \
  -L 3000:"${REMOTE_NLB}":3000 \
  -L 3001:"${REMOTE_NLB}":3001 \
  -L 9090:"${REMOTE_NLB}":9090 \
  -L 9091:"${REMOTE_NLB}":9091 \
  -L 9093:"${REMOTE_NLB}":9093 \
  "${BASTION}" -N
