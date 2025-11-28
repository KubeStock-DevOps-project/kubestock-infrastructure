#!/bin/bash
# join-cluster.sh
# Main script to join a worker node to the Kubernetes cluster
# Supports both SSM parameter retrieval and command-line arguments

set -e

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Join a worker node to the Kubernetes cluster.

Options:
    --token TOKEN           Join token (or fetched from SSM)
    --ca-cert-hash HASH     CA certificate hash (or fetched from SSM)
    --ssm                   Fetch token and hash from AWS SSM Parameter Store
    --help                  Show this help message

Examples:
    # Using SSM (recommended for ASG)
    $0 --ssm

    # Using command-line arguments
    $0 --token abcdef.0123456789abcdef --ca-cert-hash sha256:...
EOF
    exit 1
}

log() {
    echo "[$(date)] $1"
}

# Parse arguments
USE_SSM=false
TOKEN=""
CA_CERT_HASH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --token)
            TOKEN="$2"
            shift 2
            ;;
        --ca-cert-hash)
            CA_CERT_HASH="$2"
            shift 2
            ;;
        --ssm)
            USE_SSM=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

log "Starting cluster join process..."

# Step 1: Configure kubelet with instance metadata
log "Configuring kubelet..."
/usr/local/bin/configure-kubelet.sh

# Step 2: Get join credentials
if [ "$USE_SSM" = true ]; then
    log "Fetching join configuration from SSM..."
    
    # Get AWS region from instance metadata
    IMDSv2_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $IMDSv2_TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
    
    # Fetch from SSM
    TOKEN=$(aws ssm get-parameter --name "/kubestock/k8s/join-token" --with-decryption --region "$AWS_REGION" --query 'Parameter.Value' --output text)
    CA_CERT_HASH=$(aws ssm get-parameter --name "/kubestock/k8s/ca-cert-hash" --region "$AWS_REGION" --query 'Parameter.Value' --output text)
    
    if [ -z "$TOKEN" ] || [ -z "$CA_CERT_HASH" ]; then
        log "ERROR: Failed to fetch join credentials from SSM"
        exit 1
    fi
    log "Successfully retrieved join credentials from SSM"
fi

# Validate we have required parameters
if [ -z "$TOKEN" ] || [ -z "$CA_CERT_HASH" ]; then
    log "ERROR: Token and CA cert hash are required"
    usage
fi

# Step 3: Start nginx-proxy
log "Starting API server proxy..."
/usr/local/bin/start-nginx-proxy.sh

# Step 4: Join the cluster
log "Joining cluster..."
kubeadm join 127.0.0.1:6443 \
    --token "$TOKEN" \
    --discovery-token-ca-cert-hash "$CA_CERT_HASH" \
    --ignore-preflight-errors=FileAvailable--etc-kubernetes-pki-ca.crt

log "Successfully joined the cluster!"

# Step 5: Verify node is ready (optional)
log "Verifying node status..."
sleep 10
if systemctl is-active --quiet kubelet; then
    log "Kubelet is running"
else
    log "WARNING: Kubelet may not be running properly"
fi

log "Join process completed successfully"
