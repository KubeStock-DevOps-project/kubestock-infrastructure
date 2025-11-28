#!/bin/bash
# configure-kubelet.sh
# Configures kubelet with instance-specific IP and hostname from EC2 metadata
# This script should be run before kubeadm join

set -e

# IMDSv2 token
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Get instance metadata
INSTANCE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
HOSTNAME="worker-${INSTANCE_ID}"

echo "Configuring kubelet with IP: ${INSTANCE_IP}, Hostname: ${HOSTNAME}"

# Update kubelet.env with instance-specific values
cat > /etc/kubernetes/kubelet.env << EOF
KUBELET_ADDRESS="--node-ip=${INSTANCE_IP}"
KUBELET_HOSTNAME="--hostname-override=${HOSTNAME}"
KUBE_LOGTOSTDERR="--logtostderr=true"
KUBE_LOG_LEVEL="--v=2"
EOF

# Ensure hostname is set
hostnamectl set-hostname "${HOSTNAME}"

echo "Kubelet configured successfully"
