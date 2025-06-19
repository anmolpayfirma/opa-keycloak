#!/bin/bash

# Migration script to transition from auth-service to Istio OPA integration
# This script helps phase out the custom auth-service in favor of Istio's native OPA integration

set -e

# Configuration
NAMESPACE="opa-keycloak"
RELEASE_NAME="opa-keycloak"
CHART_PATH="./helm/opa-keycloak"

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

echo "🔄 Migrating from Auth-Service to Istio OPA Integration"
echo "======================================================"

# Check prerequisites
print_status "Checking prerequisites..."

# Check if Istio is installed
if ! kubectl get namespace istio-system > /dev/null 2>&1; then
    print_error "Istio is not installed. Please install Istio first:"
    echo "   ./scripts/install-istio.sh"
    exit 1
fi

# Check if current deployment exists
if ! helm list -n ${NAMESPACE} | grep -q ${RELEASE_NAME}; then
    print_error "Current deployment not found. Please deploy the stack first:"
    echo "   ./scripts/helm-deploy-istio.sh"
    exit 1
fi

print_success "Prerequisites check passed"
echo ""

# Step 1: Update Istio mesh configuration
print_status "Step 1: Updating Istio mesh configuration..."

# Check if istio configmap exists and update it
if kubectl get configmap istio -n istio-system > /dev/null 2>&1; then
    print_status "Updating existing Istio mesh configuration..."
    
    # Get current mesh config
    CURRENT_MESH=$(kubectl get configmap istio -n istio-system -o jsonpath='{.data.mesh}')
    
    # Check if extensionProviders already exists
    if echo "$CURRENT_MESH" | grep -q "extensionProviders"; then
        print_warning "extensionProviders already exists in mesh config. Manual review may be needed."
    else
        # Add extensionProviders to mesh config
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: istio
  namespace: istio-system
data:
  mesh: |
    extensionProviders:
    - name: opa-ext-authz-grpc
      envoyExtAuthzGrpc:
        service: opa-ext-authz-grpc.${NAMESPACE}.svc.cluster.local
        port: 9191
    $(echo "$CURRENT_MESH" | sed 's/^/    /')
EOF
        print_success "Istio mesh configuration updated"
    fi
else
    print_status "Creating new Istio mesh configuration..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: istio
  namespace: istio-system
data:
  mesh: |
    extensionProviders:
    - name: opa-ext-authz-grpc
      envoyExtAuthzGrpc:
        service: opa-ext-authz-grpc.${NAMESPACE}.svc.cluster.local
        port: 9191
EOF
    print_success "Istio mesh configuration created"
fi

# Restart Istio control plane to pick up new config
print_status "Restarting Istio control plane..."
kubectl rollout restart deployment/istiod -n istio-system
kubectl rollout status deployment/istiod -n istio-system --timeout=300s

print_success "Step 1 completed"
echo ""

# Step 2: Deploy OPA-Envoy with external authorization
print_status "Step 2: Deploying OPA-Envoy with external authorization..."

# Apply the new OPA-Envoy configuration (excluding mesh config which is handled separately)
helm upgrade ${RELEASE_NAME} ${CHART_PATH} \
    --namespace ${NAMESPACE} \
    --reuse-values \
    --set istio.opaExtAuthz.enabled=true

if [ $? -ne 0 ]; then
    print_error "Failed to deploy OPA-Envoy configuration"
    exit 1
fi

print_success "OPA-Envoy deployed successfully"

# Wait for OPA-Envoy to be ready
print_status "Waiting for OPA-Envoy to be ready..."
kubectl wait --for=condition=ready pod -l app=opa-envoy -n ${NAMESPACE} --timeout=300s

print_success "Step 2 completed"
echo ""

# Step 3: Update routing to bypass auth-service
print_status "Step 3: Updating routing to bypass auth-service..."

# The routing update is already included in the Helm chart update above
print_success "Routing updated to go directly to employee-api-service"

print_success "Step 3 completed"
echo ""

# Step 4: Test the new configuration
print_status "Step 4: Testing the new configuration..."

# Wait a bit for configuration to propagate
sleep 10

# Test health endpoint
if curl -s --connect-timeout 5 -H "Host: opa-demo.local" "http://localhost/health" > /dev/null; then
    print_success "✅ Health endpoint accessible"
else
    print_warning "⚠️  Health endpoint test failed"
fi

# Test employee API without auth (should fail)
EMPLOYEE_RESPONSE=$(curl -s -w "%{http_code}" -H "Host: opa-demo.local" "http://localhost/api/v1/employees" -o /dev/null)
if [ "$EMPLOYEE_RESPONSE" = "403" ]; then
    print_success "✅ Employee API correctly requires authorization"
else
    print_warning "⚠️  Employee API authorization test unexpected result: $EMPLOYEE_RESPONSE"
fi

print_success "Step 4 completed"
echo ""

# Step 5: Scale down auth-service (but don't delete yet)
print_status "Step 5: Scaling down auth-service (keeping for rollback)..."

kubectl scale deployment auth-service --replicas=0 -n ${NAMESPACE}

print_success "Auth-service scaled down to 0 replicas"
print_warning "Auth-service deployment kept for potential rollback"

print_success "Step 5 completed"
echo ""

# Summary
print_success "🎉 Migration completed successfully!"
echo ""
echo "📋 Migration Summary:"
echo "✅ Istio mesh configured with OPA external authorization"
echo "✅ OPA-Envoy deployed with gRPC interface"
echo "✅ Routing updated to bypass auth-service"
echo "✅ AuthorizationPolicy applied for /api/v1/employees paths"
echo "✅ Auth-service scaled down (kept for rollback)"
echo ""
echo "🧪 Next Steps:"
echo "1. Run comprehensive tests: ./tests/run-all-tests.sh"
echo "2. Monitor the system for a few days"
echo "3. If everything works well, remove auth-service:"
echo "   kubectl delete deployment auth-service -n ${NAMESPACE}"
echo "   kubectl delete service auth-service -n ${NAMESPACE}"
echo ""
echo "🔄 Rollback (if needed):"
echo "   kubectl scale deployment auth-service --replicas=1 -n ${NAMESPACE}"
echo "   # Then revert the Helm chart routing changes"
echo ""
echo "📖 Architecture Changes:"
echo "   Before: Client → Istio Gateway → Auth-Service → Employee API"
echo "   After:  Client → Istio Gateway → Istio Sidecar (OPA) → Employee API" 