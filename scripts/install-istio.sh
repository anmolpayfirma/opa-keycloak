#!/bin/bash

# Install Istio Service Mesh using Helm
# This script installs Istio using Helm charts for better integration

set -e

# Configuration
ISTIO_VERSION="1.26.1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Istio is already installed
if kubectl get namespace istio-system > /dev/null 2>&1; then
    if kubectl get pods -n istio-system -l app=istiod | grep -q Running; then
        print_success "Istio is already installed and running"
        exit 0
    fi
fi

print_status "Installing Istio ${ISTIO_VERSION} using Helm..."

# Add Istio Helm repository
print_status "Adding Istio Helm repository..."
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

# Create istio-system namespace
print_status "Creating istio-system namespace..."
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -

# Install Istio base chart
print_status "Installing Istio base components..."
helm upgrade --install istio-base istio/base \
    -n istio-system \
    --version ${ISTIO_VERSION} \
    --wait

# Install Istio discovery (istiod)
print_status "Installing Istio control plane (istiod)..."
helm upgrade --install istiod istio/istiod \
    -n istio-system \
    --version ${ISTIO_VERSION} \
    --wait \
    --timeout 300s

# Install Istio ingress gateway
print_status "Installing Istio ingress gateway..."
helm upgrade --install istio-ingressgateway istio/gateway \
    -n istio-system \
    --version ${ISTIO_VERSION} \
    --wait

# Verify installation
print_status "Verifying Istio installation..."
kubectl wait --for=condition=available deployment/istiod -n istio-system --timeout=300s
kubectl wait --for=condition=available deployment/istio-ingressgateway -n istio-system --timeout=300s

# Check if all components are running
print_status "Checking Istio components..."
kubectl get pods -n istio-system

# Get Gateway NodePort for reference
GATEWAY_PORT=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

print_success "🎉 Istio installation completed successfully!"
echo ""
echo "📋 Installation Summary:"
echo "✅ Istio ${ISTIO_VERSION} installed via Helm"
echo "✅ Control plane (istiod) running"
echo "✅ Ingress gateway available on NodePort: ${GATEWAY_PORT}"
echo ""
echo "🔍 Installed Helm releases:"
helm list -n istio-system
echo ""
echo "🚀 Next steps:"
echo "1. Enable sidecar injection: kubectl label namespace <namespace> istio-injection=enabled"
echo "2. Deploy your applications with Istio sidecars"
echo "3. Configure Gateway and VirtualService for traffic management"
echo ""
echo "🗑️  To uninstall: helm uninstall istio-ingressgateway istiod istio-base -n istio-system" 