#!/bin/bash

# Helm-based PostgreSQL-Enabled OPA + Keycloak Deployment Script
# Uses Helm for clean deployment management

set -e

echo "🚀 Helm-based PostgreSQL-Enabled OPA + Keycloak Deployment"
echo "==========================================================="

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

# Check if running in cloud minikube
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    print_status "Running in cloud minikube mode"
    print_status "Using SSH tunnel to minikube at $SPOT_INSTANCE_DNS_NAME"
    
    # For cloud minikube, we need to build images remotely
    BUILD_REMOTE=true
else
    print_status "Running in local minikube mode"
    BUILD_REMOTE=false
fi

# Step 1: Build Docker images
print_status "Step 1: Building Docker images..."

cd apps/employee-api

if [ "$BUILD_REMOTE" = true ]; then
    # Build on cloud minikube
    print_status "Building Employee API image on cloud minikube..."
    
    # Copy files to cloud minikube
    scp -i ~/.ssh/dev-machine.pem -o StrictHostKeyChecking=no \
        app-postgres.py requirements-postgres.txt Dockerfile-postgres \
        ubuntu@$SPOT_INSTANCE_DNS_NAME:~/
    
    # Build and push image on remote
    ssh -i ~/.ssh/dev-machine.pem -o StrictHostKeyChecking=no ubuntu@$SPOT_INSTANCE_DNS_NAME "
        eval \$(minikube docker-env)
        docker build -f Dockerfile-postgres -t localhost:5000/employee-api:v2.0.0-postgres .
        docker push localhost:5000/employee-api:v2.0.0-postgres
        echo 'Employee API image built and pushed successfully'
    "
else
    # Build locally
    print_status "Building Employee API image locally..."
    eval $(minikube docker-env)
    docker build -f Dockerfile-postgres -t localhost:5000/employee-api:v2.0.0-postgres .
    docker push localhost:5000/employee-api:v2.0.0-postgres
fi

cd ../..

# We also need to build the auth-service if it doesn't exist
cd apps/auth-service

if [ "$BUILD_REMOTE" = true ]; then
    # Build auth service on cloud minikube
    print_status "Building Auth Service image on cloud minikube..."
    
    scp -i ~/.ssh/dev-machine.pem -o StrictHostKeyChecking=no \
        app.py requirements.txt Dockerfile \
        ubuntu@$SPOT_INSTANCE_DNS_NAME:~/auth-service/
    
    ssh -i ~/.ssh/dev-machine.pem -o StrictHostKeyChecking=no ubuntu@$SPOT_INSTANCE_DNS_NAME "
        cd auth-service
        eval \$(minikube docker-env)
        docker build -t localhost:5000/auth-service:latest .
        docker push localhost:5000/auth-service:latest
        echo 'Auth Service image built and pushed successfully'
    "
else
    # Build locally
    print_status "Building Auth Service image locally..."
    eval $(minikube docker-env)
    docker build -t localhost:5000/auth-service:latest .
    docker push localhost:5000/auth-service:latest
fi

cd ../..

print_success "Docker images built and pushed successfully"

# Step 2: Validate Helm chart
print_status "Step 2: Validating Helm chart..."
helm lint $CHART_PATH
print_success "Helm chart validation passed"

# Step 3: Check if release exists and uninstall if needed
print_status "Step 3: Checking existing release..."
if helm list -n $NAMESPACE | grep -q $RELEASE_NAME; then
    print_warning "Release $RELEASE_NAME already exists. Uninstalling..."
    helm uninstall $RELEASE_NAME -n $NAMESPACE
    print_status "Waiting for resources to be cleaned up..."
    sleep 10
fi

# Step 4: Install/Upgrade with Helm
print_status "Step 4: Installing with Helm..."
helm install $RELEASE_NAME $CHART_PATH \
    --namespace $NAMESPACE \
    --create-namespace \
    --wait \
    --timeout 10m \
    --values $CHART_PATH/values.yaml

print_success "Helm installation completed"

# Step 5: Verify deployment
print_status "Step 5: Verifying deployment..."

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

# Step 6: Wait for all pods to be ready
print_status "Step 6: Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod --all -n $NAMESPACE --timeout=300s
print_success "All pods are ready"

# Step 7: Test database connectivity
print_status "Step 7: Testing database connectivity..."
DB_TEST_RESULT=$(kubectl run db-connectivity-test --image=postgres:15-alpine --rm -i --restart=Never -n $NAMESPACE -- \
    psql -h postgresql-service -U postgres -d opa_demo -c "SELECT 'Database is working!' as status;" 2>/dev/null || echo "FAILED")

if echo "$DB_TEST_RESULT" | grep -q "Database is working!"; then
    print_success "Database connectivity test passed"
else
    print_error "Database connectivity test failed"
fi

# Step 8: Test Employee API health
print_status "Step 8: Testing Employee API health..."
API_POD=$(kubectl get pod -l app=employee-api -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
if [ -n "$API_POD" ]; then
    HEALTH_RESPONSE=$(kubectl exec $API_POD -n $NAMESPACE -- curl -s http://localhost:8080/health || echo "FAILED")
    
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
echo "🎉 Helm-based PostgreSQL Deployment Complete!"
echo "=============================================="

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

if [ "$BUILD_REMOTE" = true ]; then
    echo "Add to your /etc/hosts file:"
    echo "$SPOT_INSTANCE_DNS_NAME opa-demo.local"
    echo ""
    echo "Access URLs:"
    echo "🌐 Employee API: http://opa-demo.local/api/v1/employees"
    echo "🔐 Keycloak Admin: http://opa-demo.local/keycloak/admin"
else
    MINIKUBE_IP=$(minikube ip)
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
echo "# View release history:"
echo "helm history $RELEASE_NAME -n $NAMESPACE"

echo ""
print_status "🔧 Database Management:"
echo "================================"
echo "# Connect to PostgreSQL:"
echo "kubectl run -i --tty --rm debug --image=postgres:15-alpine --restart=Never -n $NAMESPACE -- psql -h postgresql-service -U postgres -d opa_demo"
echo ""
echo "# Check database sizes:"
echo "kubectl run db-size-check --image=postgres:15-alpine --rm -i --restart=Never -n $NAMESPACE -- psql -h postgresql-service -U postgres -d opa_demo -c \"SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database WHERE datistemplate = false;\""

print_success "🚀 Your Helm-managed PostgreSQL-enabled OPA + Keycloak system is deployed!" 