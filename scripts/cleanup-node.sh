#!/bin/bash
set -x

# 1. Reset Kubernetes State
sudo kubeadm reset -f

# 2. Clean up K8s Configs and Data
sudo rm -rf /etc/kubernetes/
sudo rm -rf /var/lib/kubelet/
sudo rm -rf /var/lib/etcd/
sudo rm -rf ~/.kube/

# 3. Clean up CNI (Networking)
# DELETE the config (specific to this node's IP/network)
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/cni/
# ⚠️ IMPORTANT: KEPT /opt/cni/ because it holds the plugin binaries!

# 4. Flush iptables/IPVS to remove old K8s routing rules
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X

# 5. Clean up machine-id (CRITICAL for ASG uniqueness)
# This ensures the new instance generates a new unique ID on boot
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id

# 6. Clean cloud-init so User Data runs again
sudo cloud-init clean --logs --seed

# 7. Clean SSH host keys (regen on first boot)
sudo rm -f /etc/ssh/ssh_host_*

# 8. Clean logs (optional but good for hygiene)
sudo rm -rf /var/log/pods/*
sudo rm -rf /var/log/containers/*

# 9. Clear history and Shutdown
history -c
cat /dev/null > ~/.bash_history
echo "Cleanup complete. Shutting down for AMI creation..."
sudo shutdown -h now