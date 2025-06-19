#!/bin/bash

# Uninstall Istio Service Mesh
# This script removes Istio components installed via Helm

set -e

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

# Check if Istio is installed
if ! kubectl get namespace istio-system > /dev/null 2>&1; then
    print_warning "Istio is not installed (istio-system namespace not found)"
    exit 0
fi

print_status "Uninstalling Istio..."

# Uninstall Istio components in reverse order
print_status "Removing Istio ingress gateway..."
helm uninstall istio-ingressgateway -n istio-system 2>/dev/null || print_warning "istio-ingressgateway not found"

print_status "Removing Istio control plane (istiod)..."
helm uninstall istiod -n istio-system 2>/dev/null || print_warning "istiod not found"

print_status "Removing Istio base components..."
helm uninstall istio-base -n istio-system 2>/dev/null || print_warning "istio-base not found"

# Wait for pods to terminate
print_status "Waiting for pods to terminate..."
kubectl wait --for=delete pods --all -n istio-system --timeout=120s 2>/dev/null || true

# Remove namespace
print_status "Removing istio-system namespace..."
kubectl delete namespace istio-system 2>/dev/null || print_warning "istio-system namespace not found"

# Remove Istio Helm repository (optional)
read -p "Remove Istio Helm repository? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Removing Istio Helm repository..."
    helm repo remove istio 2>/dev/null || print_warning "Istio repo not found"
fi

print_success "🎉 Istio uninstallation completed!"
echo ""
echo "📋 Cleanup Summary:"
echo "✅ Istio components removed"
echo "✅ istio-system namespace deleted"
echo ""
echo "💡 Note: Istio sidecars in application namespaces are not affected."
echo "   To remove sidecars, restart pods or remove istio-injection label from namespaces." 