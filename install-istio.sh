#!/bin/bash
# Install and configure Istio for KubeStock Kubernetes cluster
# Usage: ./install-istio.sh [--profile=demo|production]

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
ISTIO_VERSION="1.18.0"
ISTIO_PROFILE="${1:-demo}"  # demo, production, or minimal
NAMESPACE="istio-system"
STAGING_NS="kubestock-staging"

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    # Check helm (optional)
    if ! command -v helm &> /dev/null; then
        print_warn "helm not found. Some operations may use kubectl instead."
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster."
        exit 1
    fi
    
    print_info "Prerequisites check passed."
}

# Download Istio
download_istio() {
    print_info "Downloading Istio ${ISTIO_VERSION}..."
    
    if [ ! -d "istio-${ISTIO_VERSION}" ]; then
        # Download using the official script
        curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -
        print_info "Istio ${ISTIO_VERSION} downloaded successfully."
    else
        print_warn "Istio ${ISTIO_VERSION} already exists locally."
    fi
    
    # Add istioctl to PATH
    export PATH="$PWD/istio-${ISTIO_VERSION}/bin:$PATH"
}

# Install Istio CRDs
install_istio() {
    print_info "Installing Istio with ${ISTIO_PROFILE} profile..."
    
    case $ISTIO_PROFILE in
        demo)
            print_info "Using demo profile (includes Kiali, Jaeger, Prometheus)"
            istioctl install --set profile=demo -y
            ;;
        production)
            print_info "Using production profile (minimal, optimized)"
            istioctl install --set profile=production -y
            ;;
        minimal)
            print_info "Using minimal profile"
            istioctl install --set profile=minimal -y
            ;;
        *)
            print_error "Unknown profile: ${ISTIO_PROFILE}"
            exit 1
            ;;
    esac
    
    print_info "Istio installed successfully."
}

# Wait for control plane
wait_for_istio() {
    print_info "Waiting for Istio control plane to be ready..."
    
    kubectl wait --for=condition=Ready pod \
        -l app=istiod \
        -n ${NAMESPACE} \
        --timeout=300s
    
    print_info "Istio control plane is ready."
}

# Enable sidecar injection for staging namespace
enable_sidecar_injection() {
    print_info "Enabling automatic sidecar injection for ${STAGING_NS} namespace..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace ${STAGING_NS} --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespace for sidecar injection
    kubectl label namespace ${STAGING_NS} istio-injection=enabled --overwrite
    
    print_info "Sidecar injection enabled for ${STAGING_NS} namespace."
}

# Apply KubeStock Istio configuration
apply_kubestock_config() {
    print_info "Applying KubeStock Istio configurations..."
    
    # Check if kustomize is available or use kubectl with kustomize support
    if command -v kustomize &> /dev/null; then
        kustomize build gitops/base/istio | kubectl apply -f -
    else
        kubectl apply -k gitops/base/istio
    fi
    
    print_info "KubeStock Istio configurations applied."
}

# Verify installation
verify_installation() {
    print_info "Verifying Istio installation..."
    
    # Check Istio namespace
    print_info "Checking Istio system pods..."
    kubectl get pods -n ${NAMESPACE}
    
    # Check sidecar injection label
    print_info "Checking namespace label..."
    kubectl get namespace ${STAGING_NS} -o jsonpath='{.metadata.labels.istio-injection}'
    echo ""
    
    # Check if pods have sidecars
    print_info "Checking for sidecar injection in existing pods..."
    PODS=$(kubectl get pods -n ${STAGING_NS} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    if [ -z "$PODS" ]; then
        print_warn "No pods found in ${STAGING_NS} yet. Deploy services to see sidecars."
    else
        kubectl get pods -n ${STAGING_NS} -o jsonpath='{.items[*].spec.containers[*].name}' | grep -q "istio-proxy" && \
            print_info "✓ Sidecar injection is working" || \
            print_warn "No sidecars detected yet. Redeploy pods after tagging namespace."
    fi
    
    print_info "Installation verification complete."
}

# Install optional addons (Kiali, Jaeger, Prometheus)
install_addons() {
    if [ "$ISTIO_PROFILE" = "demo" ]; then
        print_info "Installing Istio addons (Kiali, Jaeger, Prometheus)..."
        
        ISTIO_DIR="istio-${ISTIO_VERSION}"
        
        kubectl apply -f "${ISTIO_DIR}/samples/addons/prometheus.yaml"
        kubectl apply -f "${ISTIO_DIR}/samples/addons/grafana.yaml"
        kubectl apply -f "${ISTIO_DIR}/samples/addons/jaeger.yaml"
        kubectl apply -f "${ISTIO_DIR}/samples/addons/kiali.yaml"
        
        print_info "Addons installed. Access Kiali at: kubectl port-forward -n istio-system svc/kiali 20000:20000"
    fi
}

# Main execution
main() {
    print_info "Starting KubeStock Istio installation..."
    echo ""
    
    check_prerequisites
    download_istio
    install_istio
    wait_for_istio
    enable_sidecar_injection
    apply_kubestock_config
    install_addons
    verify_installation
    
    echo ""
    print_info "✓ Istio installation and configuration complete!"
    echo ""
    print_info "Next steps:"
    echo "  1. Deploy KubeStock services:"
    echo "     kubectl apply -k gitops/overlays/staging/"
    echo ""
    echo "  2. Verify sidecar injection:"
    echo "     kubectl get pods -n ${STAGING_NS} -o jsonpath='{.items[*].spec.containers[*].name}'"
    echo ""
    echo "  3. Test mTLS connectivity:"
    echo "     kubectl exec -it <pod-name> -n ${STAGING_NS} -- curl http://ms-identity:3006/health"
    echo ""
    if [ "$ISTIO_PROFILE" = "demo" ]; then
        echo "  4. Access Kiali dashboard:"
        echo "     kubectl port-forward -n istio-system svc/kiali 20000:20000"
        echo "     Then open: http://localhost:20000"
    fi
}

# Run main
main
