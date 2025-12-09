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
    TOKEN=$(aws ssm get-parameter --name "/kubestock/join-token" --with-decryption --region "$AWS_REGION" --query 'Parameter.Value' --output text)
    CA_CERT_HASH="sha256:$(aws ssm get-parameter --name "/kubestock/ca-cert-hash" --region "$AWS_REGION" --query 'Parameter.Value' --output text)"
    
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

# Step 5: Add topology labels (for EBS CSI and other topology-aware schedulers)
log "Adding topology labels..."

# Get metadata for labels
IMDSv2_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
AVAILABILITY_ZONE=$(curl -s -H "X-aws-ec2-metadata-token: $IMDSv2_TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $IMDSv2_TOKEN" http://169.254.169.254/latest/meta-data/instance-type)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $IMDSv2_TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $IMDSv2_TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
HOSTNAME="worker-${INSTANCE_ID}"

log "Adding labels: zone=$AVAILABILITY_ZONE, region=$REGION, instance-type=$INSTANCE_TYPE"

# Wait a bit for the node to be registered
sleep 15

# Try to add labels (may fail if we don't have permissions, but try anyway)
# The cloud controller manager should also add these, but this ensures they're present
kubectl label node "$HOSTNAME" \
    topology.kubernetes.io/zone="$AVAILABILITY_ZONE" \
    topology.kubernetes.io/region="$REGION" \
    node.kubernetes.io/instance-type="$INSTANCE_TYPE" \
    --overwrite 2>/dev/null || log "Note: Could not add labels via kubectl (expected if running without kubeconfig)"

# Step 6: Verify node is ready (optional)
log "Verifying node status..."
sleep 10
if systemctl is-active --quiet kubelet; then
    log "Kubelet is running"
else
    log "WARNING: Kubelet may not be running properly"
fi

log "Join process completed successfully"
