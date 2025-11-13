#!/bin/bash
set -ex

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Install required packages
apt-get install -y apt-transport-https ca-certificates curl gpg software-properties-common

# Add Docker repository for containerd
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Add Kubernetes repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

# Update package index
apt-get update -y

# Install containerd
apt-get install -y containerd.io

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart containerd
systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd

# Install Kubernetes components
apt-get install -y kubelet=1.34.1-1.1 kubeadm=1.34.1-1.1 kubectl=1.34.1-1.1
apt-mark hold kubelet kubeadm kubectl

# Configure kernel modules
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Configure sysctl
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Enable and start kubelet
systemctl enable kubelet
systemctl start kubelet

# Join the cluster
kubeadm join 10.0.10.21:6443 --token fk55xw.avt81umt66fr81m7 --discovery-token-ca-cert-hash sha256:03b036b662cbff413a8b9ecb4b45e47ed4c552ccf73318a99f5450bd307d8db0

echo "Node join completed successfully!"
