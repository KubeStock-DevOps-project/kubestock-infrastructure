#!/bin/bash
# =============================================================================
# KubeStock - Kubernetes Base Infrastructure Bootstrap Script
# =============================================================================
# This script sets up the base infrastructure components required BEFORE
# deploying applications via ArgoCD.
#
# Components:
#   1. AWS Cloud Controller Manager - Node providerID and lifecycle
#   2. AWS EBS CSI Driver - Dynamic EBS volume provisioning
#   3. StorageClass - Default storage class for PVCs
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - Nodes have IAM instance profile with EBS permissions
#   - IMDS hop limit >= 2 on worker nodes
#
# Usage:
#   ./bootstrap-k8s-base.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_BASE_DIR="${SCRIPT_DIR}"

echo "=============================================="
echo "KubeStock - Kubernetes Base Infrastructure"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl first."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
    exit 1
fi

log_info "Connected to cluster: $(kubectl config current-context)"

# Step 1: Apply AWS Cloud Controller Manager
log_info "Step 1: Deploying AWS Cloud Controller Manager..."
kubectl apply -f "${K8S_BASE_DIR}/aws-cloud-controller-manager/"
log_info "Waiting for CCM to be ready..."
kubectl rollout status daemonset/aws-cloud-controller-manager -n kube-system --timeout=120s

# Step 2: Apply AWS EBS CSI Driver
log_info "Step 2: Deploying AWS EBS CSI Driver..."
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.25"
log_info "Waiting for EBS CSI Controller to be ready..."
sleep 10
kubectl rollout status deployment/ebs-csi-controller -n kube-system --timeout=180s

# Step 3: Apply StorageClass
log_info "Step 3: Creating StorageClass..."
kubectl apply -f "${K8S_BASE_DIR}/storage-classes/"

# Verify installation
echo ""
log_info "=============================================="
log_info "Verification"
log_info "=============================================="

echo ""
log_info "Node ProviderIDs:"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.providerID}{"\n"}{end}'

echo ""
log_info "StorageClasses:"
kubectl get storageclass

echo ""
log_info "EBS CSI Driver Pods:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

echo ""
log_info "=============================================="
log_info "Bootstrap Complete!"
log_info "=============================================="
log_info "You can now deploy StatefulSets with persistent storage."
log_info "Default StorageClass: ebs-gp3"
