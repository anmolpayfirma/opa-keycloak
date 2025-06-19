#!/bin/bash

# Build Docker Images
# This script builds the necessary Docker images for the OPA-Keycloak system with PostgreSQL

set -e

echo "🐳 Building Docker Images"
echo "========================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check if we're using cloud minikube
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    print_status "Using cloud minikube at $SPOT_INSTANCE_DNS_NAME"
    REGISTRY="localhost:5000"
    
    # Set up SSH agent
    print_status "Setting up SSH agent..."
    SSH_AGENT_OUTPUT=$(ssh-agent)
    export SSH_AUTH_SOCK=$(echo "$SSH_AGENT_OUTPUT" | grep SSH_AUTH_SOCK | cut -d';' -f1 | cut -d'=' -f2)
    export SSH_AGENT_PID=$(echo "$SSH_AGENT_OUTPUT" | grep SSH_AGENT_PID | cut -d';' -f1 | cut -d'=' -f2)
    MINIKUBE_SSH_KEY=${MINIKUBE_SSH_KEY:-~/.config/cloudkube/minikube-ssh-key}
    ssh-add $MINIKUBE_SSH_KEY
    print_success "SSH agent configured"
else
    # Set up Docker environment for local minikube
    print_status "Setting up Docker environment for local minikube..."
    eval $(minikube docker-env)
    print_success "Docker environment configured for minikube"
    REGISTRY="localhost:5000"
fi

# Build Employee API
print_status "Building Employee API..."
cd apps/employee-api

if [ ! -f "Dockerfile" ]; then
    print_error "Dockerfile not found in apps/employee-api/"
    exit 1
fi

if [ ! -f "app.py" ]; then
    print_error "app.py not found in apps/employee-api/"
    exit 1
fi

print_status "Building ${REGISTRY}/employee-api:v2.0.0..."
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    docker -H ssh://docker@$SPOT_INSTANCE_DNS_NAME:2222 build -t ${REGISTRY}/employee-api:v2.0.0 .
else
    docker build -t ${REGISTRY}/employee-api:v2.0.0 .
    docker push ${REGISTRY}/employee-api:v2.0.0
fi
print_success "Employee API image built"

cd ../..

# Build Merchant API
print_status "Building Merchant API..."
cd apps/merchant-api

if [ ! -f "Dockerfile" ]; then
    print_error "Dockerfile not found in apps/merchant-api/"
    exit 1
fi

if [ ! -f "pom.xml" ]; then
    print_error "pom.xml not found in apps/merchant-api/"
    exit 1
fi

print_status "Building ${REGISTRY}/merchant-api:latest..."
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    docker -H ssh://docker@$SPOT_INSTANCE_DNS_NAME:2222 build -t ${REGISTRY}/merchant-api:latest .
else
    docker build -t ${REGISTRY}/merchant-api:latest .
    docker push ${REGISTRY}/merchant-api:latest
fi
print_success "Merchant API image built"

cd ../..

# Clean up SSH agent if we used it
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    kill $SSH_AGENT_PID 2>/dev/null || true
    print_success "SSH agent cleaned up"
fi

# Auth Service has been removed - migrated to Istio OPA Integration
print_status "Auth Service has been migrated to Istio OPA Integration"
print_status "No longer building auth-service - using native Istio authorization"

# Verify images
print_status "Verifying built images..."
echo ""
print_status "Available images in minikube registry:"
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    docker -H ssh://docker@$SPOT_INSTANCE_DNS_NAME:2222 images | grep -E "employee-api|merchant-api" || print_warning "No matching images found"
else
    docker images | grep -E "employee-api|merchant-api" || print_warning "No matching images found"
fi

echo ""
print_success "🎉 Docker images built successfully!"
echo ""
print_status "Built images:"
echo "  📦 ${REGISTRY}/employee-api:v2.0.0"
echo "  📦 ${REGISTRY}/merchant-api:latest"
echo ""
print_status "ℹ️  Auth-service replaced by Istio OPA external authorization"
echo ""
print_status "These images are now available in your minikube Docker registry"
print_status "and can be used by the Helm deployment."

echo ""
print_status "Next steps:"
echo "1. Deploy with Helm: ./scripts/helm-deploy-clean.sh"
echo "2. Test the deployment: ./tests/run-all-tests.sh" 