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

# Set up Docker environment for minikube
print_status "Setting up Docker environment for minikube..."
eval $(minikube docker-env)
print_success "Docker environment configured for minikube"

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

print_status "Building localhost:5000/employee-api:v2.0.0..."
docker build -t localhost:5000/employee-api:v2.0.0 .
docker push localhost:5000/employee-api:v2.0.0
print_success "Employee API image built and pushed"

cd ../..

# Auth Service has been removed - migrated to Istio OPA Integration
print_status "Auth Service has been migrated to Istio OPA Integration"
print_status "No longer building auth-service - using native Istio authorization"

# Verify images
print_status "Verifying built images..."
echo ""
print_status "Available images in minikube registry:"
docker images | grep -E "employee-api" || print_warning "No matching images found"

echo ""
print_success "🎉 Docker images built successfully!"
echo ""
print_status "Built images:"
echo "  📦 localhost:5000/employee-api:v2.0.0"
echo ""
print_status "ℹ️  Auth-service replaced by Istio OPA external authorization"
echo ""
print_status "These images are now available in your minikube Docker registry"
print_status "and can be used by the Helm deployment."

echo ""
print_status "Next steps:"
echo "1. Deploy with Helm: ./scripts/helm-deploy-simple.sh"
echo "2. Test the deployment: ./scripts/test-database-setup.sh" 