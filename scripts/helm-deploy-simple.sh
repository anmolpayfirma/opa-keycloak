#!/bin/bash

# Simple Helm-based PostgreSQL Deployment Script
# Assumes Docker images are already built and available

set -e

echo "🚀 Simple Helm PostgreSQL Deployment"
echo "===================================="

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

# Configuration
RELEASE_NAME="opa-keycloak-postgres"
CHART_PATH="./helm/opa-keycloak-postgres"
NAMESPACE="default"

print_status "Using Helm to deploy PostgreSQL-enabled OPA + Keycloak system"

# Step 1: Validate Helm chart
print_status "Step 1: Validating Helm chart..."
helm lint $CHART_PATH
print_success "Helm chart validation passed"

# Step 2: Check if release exists and uninstall if needed
print_status "Step 2: Checking existing release..."
if helm list -n $NAMESPACE | grep -q $RELEASE_NAME; then
    print_warning "Release $RELEASE_NAME already exists. Uninstalling..."
    helm uninstall $RELEASE_NAME -n $NAMESPACE
    print_status "Waiting for resources to be cleaned up..."
    sleep 10
fi

# Step 3: Install with Helm
print_status "Step 3: Installing with Helm..."
helm install $RELEASE_NAME $CHART_PATH \
    --namespace $NAMESPACE \
    --create-namespace \
    --wait \
    --timeout 10m \
    --values $CHART_PATH/values.yaml

print_success "Helm installation completed"

# Step 4: Verify deployment
print_status "Step 4: Verifying deployment..."

echo ""
print_status "Checking all pods..."
kubectl get pods -n $NAMESPACE

echo ""
print_status "Checking all services..."
kubectl get services -n $NAMESPACE

echo ""
print_status "Checking persistent volumes..."
kubectl get pvc -n $NAMESPACE

echo ""
print_status "Checking ingress..."
kubectl get ingress -n $NAMESPACE

# Step 5: Wait for PostgreSQL to be ready first
print_status "Step 5: Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql -n $NAMESPACE --timeout=300s
print_success "PostgreSQL is ready"

# Step 6: Test database connectivity
print_status "Step 6: Testing database connectivity..."
DB_TEST_RESULT=$(kubectl run db-connectivity-test --image=postgres:15-alpine --rm -i --restart=Never -n $NAMESPACE -- \
    psql -h postgresql-service -U postgres -d opa_demo -c "SELECT 'Database is working!' as status;" 2>/dev/null || echo "FAILED")

if echo "$DB_TEST_RESULT" | grep -q "Database is working!"; then
    print_success "Database connectivity test passed"
else
    print_error "Database connectivity test failed"
    print_status "Database logs:"
    kubectl logs -l app=postgresql -n $NAMESPACE --tail=20
fi

# Step 7: Wait for all other pods
print_status "Step 7: Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod --all -n $NAMESPACE --timeout=300s
print_success "All pods are ready"

# Step 8: Test Employee API health (if available)
print_status "Step 8: Testing Employee API health..."
API_POD=$(kubectl get pod -l app=employee-api -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$API_POD" ]; then
    HEALTH_RESPONSE=$(kubectl exec $API_POD -n $NAMESPACE -- curl -s http://localhost:8080/health 2>/dev/null || echo "FAILED")
    
    if echo "$HEALTH_RESPONSE" | grep -q '"status":"healthy"'; then
        print_success "Employee API health check passed"
    else
        print_warning "Employee API health check failed or not ready yet"
        echo "Response: $HEALTH_RESPONSE"
        print_status "Employee API logs:"
        kubectl logs $API_POD -n $NAMESPACE --tail=10
    fi
else
    print_warning "Employee API pod not found (image may not be available)"
fi

# Summary
echo ""
echo "🎉 Helm PostgreSQL Deployment Complete!"
echo "======================================="

print_success "✅ PostgreSQL deployed with persistent storage"
print_success "✅ Keycloak deployed with PostgreSQL backend"
print_success "✅ OPA policy engine deployed"
print_success "✅ Auth Service deployed"
print_success "✅ Kong Gateway deployed"
print_success "✅ NGINX Ingress configured"

if [ -n "$API_POD" ]; then
    print_success "✅ Employee API deployed with PostgreSQL integration"
else
    print_warning "⚠️  Employee API not deployed (Docker image needs to be built)"
fi

echo ""
print_status "🔗 Access Information:"
echo "================================"

if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    echo "Add to your /etc/hosts file:"
    echo "192.168.49.2 opa-demo.local"
    echo ""
    echo "Access URLs (through SSH tunnel):"
    echo "🌐 Employee API: http://opa-demo.local/api/v1/employees"
    echo "🔐 Keycloak Admin: http://opa-demo.local/keycloak/admin"
else
    MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "192.168.49.2")
    echo "Add to your /etc/hosts file:"
    echo "$MINIKUBE_IP opa-demo.local"
    echo ""
    echo "Access URLs:"
    echo "🌐 Employee API: http://opa-demo.local/api/v1/employees"
    echo "🔐 Keycloak Admin: http://opa-demo.local/keycloak/admin"
fi

echo ""
print_status "🧪 Testing Commands:"
echo "================================"
echo "1. Test database setup:"
echo "   ./scripts/test-database-setup.sh"
echo ""
echo "2. Test CRUD operations:"
echo "   ./scripts/test-crud-operations.sh"

echo ""
print_status "📊 Helm Management Commands:"
echo "================================"
echo "# Check release status:"
echo "helm status $RELEASE_NAME -n $NAMESPACE"
echo ""
echo "# Upgrade release:"
echo "helm upgrade $RELEASE_NAME $CHART_PATH -n $NAMESPACE"
echo ""
echo "# Uninstall release:"
echo "helm uninstall $RELEASE_NAME -n $NAMESPACE"
echo ""
echo "# View all resources:"
echo "kubectl get all -l app.kubernetes.io/instance=$RELEASE_NAME -n $NAMESPACE"

echo ""
print_status "🔧 Build Docker Images (if needed):"
echo "================================"
echo "# For Employee API:"
echo "cd apps/employee-api"
echo "eval \$(minikube docker-env)"
echo "docker build -f Dockerfile-postgres -t localhost:5000/employee-api:v2.0.0-postgres ."
echo "docker push localhost:5000/employee-api:v2.0.0-postgres"
echo ""
echo "# For Auth Service:"
echo "cd apps/auth-service"
echo "docker build -t localhost:5000/auth-service:latest ."
echo "docker push localhost:5000/auth-service:latest"

print_success "🚀 Your Helm-managed PostgreSQL system is deployed!"
print_status "💡 Tip: If some services show image pull errors, build the Docker images first using the commands above." 