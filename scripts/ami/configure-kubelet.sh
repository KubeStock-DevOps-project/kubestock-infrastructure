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

# Update only the node-ip and hostname in kubelet.env, preserving other settings
KUBELET_ENV="/etc/kubernetes/kubelet.env"
KUBELET_CONFIG="/etc/kubernetes/kubelet-config.yaml"

if [ -f "$KUBELET_ENV" ]; then
    # Update existing values using sed
    sed -i "s|^KUBELET_ADDRESS=.*|KUBELET_ADDRESS=\"--node-ip=${INSTANCE_IP}\"|" "$KUBELET_ENV"
    sed -i "s|^KUBELET_HOSTNAME=.*|KUBELET_HOSTNAME=\"--hostname-override=${HOSTNAME}\"|" "$KUBELET_ENV"
else
    # Create minimal kubelet.env if it doesn't exist
    cat > "$KUBELET_ENV" << EOF
KUBE_LOG_LEVEL="--v=2"
KUBELET_ADDRESS="--node-ip=${INSTANCE_IP}"
KUBELET_HOSTNAME="--hostname-override=${HOSTNAME}"

KUBELET_ARGS="--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf \
--config=/etc/kubernetes/kubelet-config.yaml \
--kubeconfig=/etc/kubernetes/kubelet.conf \
--runtime-cgroups=/system.slice/containerd.service \
 "
KUBELET_CLOUDPROVIDER=""

PATH=/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
fi

# Update kubelet-config.yaml with correct address
if [ -f "$KUBELET_CONFIG" ]; then
    sed -i "s|^address:.*|address: \"${INSTANCE_IP}\"|" "$KUBELET_CONFIG"
fi

# Ensure hostname is set
hostnamectl set-hostname "${HOSTNAME}"

echo "Kubelet configured successfully"
