#!/bin/bash

# OPA-Keycloak Deployment Script with Istio Service Mesh
# This script deploys the OPA-Keycloak stack using Istio for traffic management

set -e

# Configuration
NAMESPACE="opa-keycloak"
RELEASE_NAME="opa-keycloak"
CHART_PATH="./helm/opa-keycloak"
REGISTRY="localhost:5000"

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

# Check if Istio is installed, install if needed
print_status "Checking Istio installation..."
if ! kubectl get namespace istio-system > /dev/null 2>&1 || ! kubectl get pods -n istio-system -l app=istiod | grep -q Running; then
    print_status "Istio not found. Installing Istio..."
    ./scripts/install-istio.sh
    if [ $? -ne 0 ]; then
        print_error "Failed to install Istio"
        exit 1
    fi
else
    print_success "Istio is already installed and running"
fi

# Clean up any existing deployment
print_status "Cleaning up existing deployment..."
helm uninstall ${RELEASE_NAME} -n ${NAMESPACE} 2>/dev/null || true
kubectl delete namespace ${NAMESPACE} 2>/dev/null || true

# Wait for cleanup
print_status "Waiting for cleanup to complete..."
sleep 10

# Create namespace with Istio injection
print_status "Creating namespace with Istio sidecar injection..."
kubectl create namespace ${NAMESPACE}
kubectl label namespace ${NAMESPACE} istio-injection=enabled

# Build Docker images
print_status "Building Docker images..."

# Build Employee API
print_status "Building Employee API..."
cd apps/employee-api
eval $(minikube docker-env)
docker build -f Dockerfile -t ${REGISTRY}/employee-api:v2.0.0 .
cd ../..

# Build Auth Service
print_status "Building Auth Service..."
cd apps/auth-service
eval $(minikube docker-env)
docker build -t ${REGISTRY}/auth-service:latest .
cd ../..

print_success "Docker images built successfully"

# Install Helm chart
print_status "Installing Helm chart with Istio configuration..."
helm install ${RELEASE_NAME} ${CHART_PATH} \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --wait \
    --timeout 5m \
    --set global.namespace=${NAMESPACE} \
    --set employeeApi.image=${REGISTRY}/employee-api:v2.0.0 \
    --set employeeApi.imagePullPolicy=IfNotPresent \
    --set authService.image=${REGISTRY}/auth-service:latest \
    --set authService.imagePullPolicy=IfNotPresent \
    --set istio.enabled=true \
    --set kong.enabled=false

if [ $? -ne 0 ]; then
    print_error "Helm installation failed"
    exit 1
fi

print_success "Helm chart installed successfully"

# Wait for pods to be ready
print_status "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod --all -n ${NAMESPACE} --timeout=300s

# Verify deployment
print_status "Verifying deployment..."
kubectl get pods -n ${NAMESPACE}

# Check Istio Gateway and VirtualService
print_status "Checking Istio configuration..."
kubectl get gateway,virtualservice -n ${NAMESPACE}

# Get Istio Gateway external port
GATEWAY_PORT=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
print_success "Istio Gateway is available on NodePort: ${GATEWAY_PORT}"

# Final status
print_success "🎉 Deployment completed successfully!"
echo ""
echo "📋 Deployment Summary:"
echo "✅ Istio Service Mesh"
echo "✅ Keycloak with PostgreSQL"
echo "✅ Employee API with Authentication"
echo "✅ OPA Policy Engine"
echo ""
echo "🚀 Access your services:"
echo "   Set up SSH tunnel: ./scripts/setup-tunnel.sh"
echo "   Keycloak: http://opa-demo.local/auth/"
echo "   Admin Console: http://opa-demo.local/auth/admin/ (admin/admin123)"
echo "   Employee API: http://opa-demo.local/api/v1/employees"
echo "   Health Check: http://opa-demo.local/health"
echo ""
echo "🧪 Test the setup: ./scripts/test-istio-setup.sh"
echo ""
echo "📖 For troubleshooting:"
echo "   kubectl get pods -n ${NAMESPACE}"
echo "   kubectl logs -l app=keycloak -n ${NAMESPACE}"
echo "   kubectl get gateway,virtualservice -n ${NAMESPACE}" 