#!/bin/bash
# ==================================================
# KubeStock - Start ALL SSH Tunnels (Linux/Mac)
# ==================================================
# This script opens SSH tunnels for all commonly used
# KubeStock endpoints in a single SSH session:
#
# - Staging (HTTP):            http://localhost:5173  -> NLB:81 (Kong staging)
# - Kubernetes API:            https://localhost:6443
# - ArgoCD UI:                 https://localhost:8443
# - Grafana (prod):            http://localhost:3000
# - Prometheus (prod):         http://localhost:9090
# - Alertmanager (prod only):  http://localhost:9093
# - Kiali (Istio UI):          http://localhost:20001
#
# NOTE: Production traffic goes through ALB with TLS termination
#       Use https://kubestock.dpiyumal.me for production access
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
echo "  Staging (HTTP):      http://localhost:5173  -> NLB:81 (Kong staging)"
echo "  Kubernetes API:      https://localhost:6443 -> NLB:6443"
echo "  ArgoCD UI:           https://localhost:8443 -> NLB:8443"
echo "  Grafana (prod):      http://localhost:3000  -> NLB:3000"
echo "  Prometheus (prod):   http://localhost:9090  -> NLB:9090"
echo "  Alertmanager (prod): http://localhost:9093  -> NLB:9093"
echo "  Kiali (Istio UI):    http://localhost:20001 -> NLB:20001"
echo ""
echo "NOTE: For production access, use https://kubestock.dpiyumal.me"
echo "      (ALB handles TLS termination)"
echo "========================================"
echo "Press Ctrl+C to close ALL tunnels."
echo ""

# Single SSH session with multiple local forwards.
# This keeps things simple and ensures all tunnels
# start and stop together.
#
# Port mappings:
#   5173 -> NLB:81  = Kong Staging (HTTP)
#   6443 -> NLB:6443 = Kubernetes API
#   8443 -> NLB:8443 = ArgoCD
#   3000 -> NLB:3000 = Grafana (prod)
#   9090 -> NLB:9090 = Prometheus (prod)
#   9093 -> NLB:9093 = Alertmanager (prod)
#   20001 -> NLB:20001 = Kiali
#
# NOTE: Production is accessed via ALB at https://kubestock.dpiyumal.me
ssh -i "${KEY_PATH}" \
  -L 5173:"${REMOTE_NLB}":81 \
  -L 6443:"${REMOTE_NLB}":6443 \
  -L 8443:"${REMOTE_NLB}":8443 \
  -L 3000:"${REMOTE_NLB}":3000 \
  -L 9090:"${REMOTE_NLB}":9090 \
  -L 9093:"${REMOTE_NLB}":9093 \
  -L 20001:"${REMOTE_NLB}":20001 \
  "${BASTION}" -N
