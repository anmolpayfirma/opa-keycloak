#!/bin/bash

# PostgreSQL-Enabled OPA + Keycloak Deployment Script
# Deploys the complete system with persistent database storage

set -e

echo "🚀 PostgreSQL-Enabled OPA + Keycloak Deployment"
echo "================================================"

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

# Check if running in cloud minikube
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    print_status "Running in cloud minikube mode"
    KUBECTL_CMD="ssh -o StrictHostKeyChecking=no ubuntu@$SPOT_INSTANCE_DNS_NAME kubectl"
    DOCKER_CMD="ssh -o StrictHostKeyChecking=no ubuntu@$SPOT_INSTANCE_DNS_NAME docker"
else
    print_status "Running in local minikube mode"
    KUBECTL_CMD="kubectl"
    DOCKER_CMD="docker"
fi

# Build Employee API with PostgreSQL support
print_status "Step 1: Building Employee API with PostgreSQL support..."
cd apps/employee-api

if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    # Copy files to remote and build there
    print_status "Copying files to cloud minikube..."
    scp -o StrictHostKeyChecking=no app-postgres.py requirements-postgres.txt Dockerfile-postgres ubuntu@$SPOT_INSTANCE_DNS_NAME:~/
    
    ssh -o StrictHostKeyChecking=no ubuntu@$SPOT_INSTANCE_DNS_NAME "
        eval \$(minikube docker-env)
        docker build -f Dockerfile-postgres -t localhost:5000/employee-api:v2.0.0-postgres .
        docker push localhost:5000/employee-api:v2.0.0-postgres
    "
else
    # Local build
    eval $(minikube docker-env)
    docker build -f Dockerfile-postgres -t localhost:5000/employee-api:v2.0.0-postgres .
    docker push localhost:5000/employee-api:v2.0.0-postgres
fi

cd ../..

print_success "Employee API Docker image built and pushed"

# Deploy PostgreSQL first
print_status "Step 2: Deploying PostgreSQL..."
$KUBECTL_CMD apply -f k8s/manifests/postgresql.yaml

print_status "Waiting for PostgreSQL to be ready..."
$KUBECTL_CMD wait --for=condition=ready pod -l app=postgresql --timeout=300s
print_success "PostgreSQL is ready"

# Deploy Keycloak with PostgreSQL
print_status "Step 3: Deploying Keycloak with PostgreSQL..."
$KUBECTL_CMD apply -f k8s/manifests/keycloak-deployment-postgres.yaml

print_status "Waiting for Keycloak to be ready..."
$KUBECTL_CMD wait --for=condition=ready pod -l app=keycloak --timeout=300s
print_success "Keycloak is ready"

# Deploy OPA
print_status "Step 4: Deploying OPA..."
$KUBECTL_CMD apply -f k8s/manifests/opa-policies.yaml

print_status "Waiting for OPA to be ready..."
$KUBECTL_CMD wait --for=condition=ready pod -l app=opa --timeout=120s
print_success "OPA is ready"

# Deploy Auth Service
print_status "Step 5: Deploying Auth Service..."
$KUBECTL_CMD apply -f k8s/manifests/auth-service.yaml

print_status "Waiting for Auth Service to be ready..."
$KUBECTL_CMD wait --for=condition=ready pod -l app=auth-service --timeout=120s
print_success "Auth Service is ready"

# Deploy Employee API with PostgreSQL
print_status "Step 6: Deploying Employee API with PostgreSQL..."
$KUBECTL_CMD apply -f k8s/manifests/employee-api-postgres.yaml

print_status "Waiting for Employee API to be ready..."
$KUBECTL_CMD wait --for=condition=ready pod -l app=employee-api --timeout=120s
print_success "Employee API is ready"

# Deploy Kong Gateway
print_status "Step 7: Deploying Kong Gateway..."
$KUBECTL_CMD apply -f k8s/manifests/kong-gateway-simple.yaml

print_status "Waiting for Kong Gateway to be ready..."
$KUBECTL_CMD wait --for=condition=ready pod -l app=kong --timeout=120s
print_success "Kong Gateway is ready"

# Deploy Ingress
print_status "Step 8: Deploying Ingress..."
$KUBECTL_CMD apply -f k8s/manifests/kong-ingress.yaml

print_success "Ingress deployed"

# Setup Keycloak configuration
print_status "Step 9: Setting up Keycloak configuration..."
if [ -f "scripts/setup-keycloak.sh" ]; then
    ./scripts/setup-keycloak.sh
    print_success "Keycloak configuration completed"
else
    print_warning "Keycloak setup script not found. You may need to configure Keycloak manually."
fi

# Verify deployment
print_status "Step 10: Verifying deployment..."

echo ""
print_status "Checking all pods..."
$KUBECTL_CMD get pods

echo ""
print_status "Checking all services..."
$KUBECTL_CMD get services

echo ""
print_status "Checking persistent volumes..."
$KUBECTL_CMD get pvc

echo ""
print_status "Checking ingress..."
$KUBECTL_CMD get ingress

# Test database connectivity
print_status "Step 11: Testing database connectivity..."
DB_TEST_RESULT=$($KUBECTL_CMD run db-connectivity-test --image=postgres:15-alpine --rm -i --restart=Never -- \
    psql -h postgresql-service -U postgres -d opa_demo -c "SELECT 'Database is working!' as status;" 2>/dev/null || echo "FAILED")

if echo "$DB_TEST_RESULT" | grep -q "Database is working!"; then
    print_success "Database connectivity test passed"
else
    print_error "Database connectivity test failed"
fi

# Test Employee API health
print_status "Step 12: Testing Employee API health..."
API_POD=$($KUBECTL_CMD get pod -l app=employee-api -o jsonpath='{.items[0].metadata.name}')
if [ -n "$API_POD" ]; then
    HEALTH_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s http://localhost:8080/health || echo "FAILED")
    
    if echo "$HEALTH_RESPONSE" | grep -q '"status":"healthy"'; then
        print_success "Employee API health check passed"
    else
        print_warning "Employee API health check failed or not ready yet"
        echo "Response: $HEALTH_RESPONSE"
    fi
else
    print_error "Employee API pod not found"
fi

# Summary
echo ""
echo "🎉 PostgreSQL-Enabled Deployment Complete!"
echo "=========================================="

print_success "✅ PostgreSQL deployed with persistent storage"
print_success "✅ Keycloak deployed with PostgreSQL backend"
print_success "✅ Employee API deployed with PostgreSQL integration"
print_success "✅ OPA policy engine deployed"
print_success "✅ Auth Service deployed"
print_success "✅ Kong Gateway deployed"
print_success "✅ NGINX Ingress configured"

echo ""
print_status "🔗 Access Information:"
echo "================================"

if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    echo "Add to your /etc/hosts file:"
    echo "$SPOT_INSTANCE_DNS_NAME opa-demo.local"
    echo ""
    echo "Access URLs:"
    echo "🌐 Employee API: http://opa-demo.local/api/v1/employees"
    echo "🔐 Keycloak Admin: http://opa-demo.local/keycloak/admin"
    echo "📊 Kong Manager: http://opa-demo.local:8002"
else
    MINIKUBE_IP=$(minikube ip)
    echo "Add to your /etc/hosts file:"
    echo "$MINIKUBE_IP opa-demo.local"
    echo ""
    echo "Access URLs:"
    echo "🌐 Employee API: http://opa-demo.local/api/v1/employees"
    echo "🔐 Keycloak Admin: http://opa-demo.local/keycloak/admin"
    echo "📊 Kong Manager: http://opa-demo.local:8002"
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
echo "3. Test authorization:"
echo "   ./scripts/test-authorization-postgres.sh"

echo ""
print_status "📊 Database Information:"
echo "================================"
echo "🗄️  PostgreSQL Version: 15"
echo "💾 Storage: 5Gi persistent volume"
echo "🔗 Connection: postgresql-service:5432"
echo "📋 Databases:"
echo "   - keycloak (Keycloak data)"
echo "   - employee_api (Employee data)"
echo "   - opa_demo (Main database)"

echo ""
print_status "🔧 Management Commands:"
echo "================================"
echo "# Connect to PostgreSQL:"
echo "kubectl run -i --tty --rm debug --image=postgres:15-alpine --restart=Never -- psql -h postgresql-service -U postgres -d opa_demo"
echo ""
echo "# Check database sizes:"
echo "kubectl run db-size-check --image=postgres:15-alpine --rm -i --restart=Never -- psql -h postgresql-service -U postgres -d opa_demo -c \"SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database WHERE datistemplate = false;\""
echo ""
echo "# Backup database:"
echo "kubectl exec -i \$(kubectl get pod -l app=postgresql -o jsonpath='{.items[0].metadata.name}') -- pg_dump -U postgres opa_demo > backup.sql"

print_success "🚀 Your production-ready PostgreSQL-enabled OPA + Keycloak system is deployed!" 