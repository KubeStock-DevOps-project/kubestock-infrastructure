#!/bin/bash
# prepare-ami.sh
# Prepares a worker node for AMI creation by:
# 1. Running kubeadm reset
# 2. Cleaning node-specific files
# 3. Installing scripts and configurations
# 4. Ensuring required packages are installed
#
# Run this on a freshly joined worker node before creating an AMI

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[$(date)] $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

log "=== Preparing node for AMI creation ==="

# Step 1: Drain the node (if kubectl is available and configured)
log "Note: Please drain this node from the control plane before continuing"
read -p "Has the node been drained? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Please drain the node first: kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data"
    exit 1
fi

# Step 2: Reset kubeadm
log "Running kubeadm reset..."
kubeadm reset -f

# Step 3: Stop services
log "Stopping services..."
systemctl stop kubelet || true
systemctl stop containerd || true

# Step 4: Clean node-specific files
log "Cleaning node-specific files..."

# Remove kubelet bootstrap data
rm -rf /etc/kubernetes/kubelet.conf
rm -rf /etc/kubernetes/bootstrap-kubelet.conf
rm -rf /etc/kubernetes/pki/ca.crt  # Will be recreated during join
rm -rf /var/lib/kubelet/pki/

# Clean kubelet data but keep configuration
rm -rf /var/lib/kubelet/pods/*
rm -f /var/lib/kubelet/cpu_manager_state
rm -f /var/lib/kubelet/memory_manager_state

# Remove CNI state
rm -rf /var/lib/cni/*
rm -rf /var/run/calico/*
rm -rf /run/calico/*

# Clean container runtime
nerdctl rm -f $(nerdctl ps -aq) 2>/dev/null || true
nerdctl system prune -af 2>/dev/null || true

# Remove SSH host keys (will be regenerated on boot)
rm -f /etc/ssh/ssh_host_*

# Clear cloud-init state for fresh run
cloud-init clean --logs 2>/dev/null || true

# Remove machine-id (will be regenerated)
echo "" > /etc/machine-id

# Step 5: Install required packages
log "Installing required packages..."
apt-get update
apt-get install -y jq awscli

# Step 6: Install scripts
log "Installing scripts..."
if [ -d "$SCRIPT_DIR" ]; then
    cp "$SCRIPT_DIR/configure-kubelet.sh" /usr/local/bin/
    cp "$SCRIPT_DIR/start-nginx-proxy.sh" /usr/local/bin/
    cp "$SCRIPT_DIR/join-cluster.sh" /usr/local/bin/
    chmod +x /usr/local/bin/configure-kubelet.sh
    chmod +x /usr/local/bin/start-nginx-proxy.sh
    chmod +x /usr/local/bin/join-cluster.sh
fi

# Step 7: Install nginx configuration
log "Installing nginx configuration..."
mkdir -p /etc/nginx
if [ -f "$SCRIPT_DIR/nginx.conf" ]; then
    cp "$SCRIPT_DIR/nginx.conf" /etc/nginx/nginx.conf
fi

# Step 8: Install systemd service
log "Installing systemd services..."
if [ -f "$SCRIPT_DIR/nginx-proxy.service" ]; then
    cp "$SCRIPT_DIR/nginx-proxy.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable nginx-proxy.service
fi

# Step 9: Pre-pull required images
log "Pre-pulling required images..."
systemctl start containerd
sleep 5
nerdctl pull docker.io/library/nginx:1.28.0-alpine

# Step 10: Restore CA certificate (needs to be copied from control plane)
log "Setting up CA certificate placeholder..."
mkdir -p /etc/kubernetes/ssl
mkdir -p /etc/kubernetes/pki
# Note: CA cert should be copied separately
if [ ! -f /etc/kubernetes/ssl/ca.crt ]; then
    log "WARNING: /etc/kubernetes/ssl/ca.crt not found"
    log "Please copy CA cert from control plane: /etc/kubernetes/ssl/ca.crt"
fi

# Create symlink for kubeadm
if [ -f /etc/kubernetes/ssl/ca.crt ]; then
    ln -sf /etc/kubernetes/ssl/ca.crt /etc/kubernetes/pki/ca.crt
fi

# Step 11: Clear logs and history
log "Clearing logs and history..."
journalctl --rotate
journalctl --vacuum-time=1s
rm -rf /var/log/*.gz
rm -rf /var/log/*.1
cat /dev/null > ~/.bash_history
history -c

log "=== AMI preparation complete ==="
log ""
log "Next steps:"
log "1. Verify CA certificate is at /etc/kubernetes/ssl/ca.crt"
log "2. Update nginx.conf with correct control plane IP if needed"
log "3. Create AMI from this instance"
log ""
log "CA cert command: scp master-1:/etc/kubernetes/ssl/ca.crt /etc/kubernetes/ssl/"
