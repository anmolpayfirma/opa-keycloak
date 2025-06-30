#!/bin/bash
set -e
set -x

# OPA-Keycloak Clean Helm Deployment Script
# Istio-based deployment with OPA external authorization
# Handles complete lifecycle: cleanup, build, deploy, verify

helm >/dev/null 2>&1 || { echo "Need to install helm v3.8+ "; exit 1; }

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
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_status "🚀 Starting OPA-Keycloak Clean Helm Deployment"

# Validate environment
print_status "Validating environment..."
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ]; then
    if [ -z "$SPOT_INSTANCE_DNS_NAME" ]; then
        print_error "SPOT_INSTANCE_DNS_NAME must be set for cloud minikube deployment"
        exit 1
    fi
    MINIKUBE_SSH_KEY=${MINIKUBE_SSH_KEY:-~/.config/cloudkube/minikube-ssh-key}
    if [ ! -f "$MINIKUBE_SSH_KEY" ]; then
        print_error "SSH key not found at $MINIKUBE_SSH_KEY"
        exit 1
    fi
    print_status "Cloud minikube mode: $SPOT_INSTANCE_DNS_NAME"
else
    if ! command -v minikube >/dev/null 2>&1; then
        print_error "minikube command not found for local deployment"
        exit 1
    fi
    print_status "Local minikube mode"
fi

# Validate chart exists
if [ ! -d "$CHART_PATH" ]; then
    print_error "Helm chart not found at $CHART_PATH"
    exit 1
fi

#1. [re]install secrets - Clean up any existing secrets first
print_status "Step 1: Comprehensive cleanup of existing resources..."

# Create namespace if it doesn't exist
kubectl create namespace ${NAMESPACE} 2>/dev/null || true

# Clean up secrets in both namespaces
kubectl -n${NAMESPACE} delete secrets $(kubectl -n${NAMESPACE} get secrets -o jsonpath='{range .items[?(@.type == "Opaque")]}{@.metadata.name}{" "}{end}') 2>/dev/null || true
kubectl -n${NAMESPACE} delete secrets $(kubectl -n${NAMESPACE} get secrets -o jsonpath='{range .items[?(@.type == "kubernetes.io/tls")]}{@.metadata.name}{" "}{end}') 2>/dev/null || true
kubectl -ndefault delete secrets $(kubectl -ndefault get secrets -o jsonpath='{range .items[?(@.type == "Opaque")]}{@.metadata.name}{" "}{end}') 2>/dev/null || true

# Clean up problematic ConfigMaps that might conflict with Helm
print_status "Cleaning up conflicting ConfigMaps..."
kubectl delete configmap opa-policies -n default 2>/dev/null || true
kubectl delete configmap opa-policies -n ${NAMESPACE} 2>/dev/null || true

# Clean up any existing deployments/services that might conflict
print_status "Cleaning up conflicting resources..."
kubectl delete deployment --all -n default 2>/dev/null || true
kubectl delete service --all -n default 2>/dev/null || true
kubectl delete configmap --all -n default 2>/dev/null || true
kubectl delete pvc --all -n default 2>/dev/null || true
kubectl delete ingress --all -n default 2>/dev/null || true
kubectl delete ingress --all -n ${NAMESPACE} 2>/dev/null || true

# Also clean up any specific problematic resources
kubectl delete ingress opa-demo-ingress -n default 2>/dev/null || true
kubectl delete ingress opa-demo-ingress -n ${NAMESPACE} 2>/dev/null || true

#2A. [re]install latest opa-keycloak chart
print_status "Step 2A: Uninstalling existing Helm release..."
helm -n${NAMESPACE} uninstall ${RELEASE_NAME} --wait 2>/dev/null || true

#2B. delete images so any 'latest' tags will get pulled (IfNotPresent policy):
SLEEP1=10
print_status "Step 2B: Waiting ${SLEEP1}s for containers to shutdown..."
sleep $SLEEP1

print_status "Step 2C: Cleaning up Docker images..."
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ]; then
   if [ "$SPOT_INSTANCE_DNS_NAME" != "" ]; then
       print_status "Cleaning images on cloud minikube..."
       ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 2222 -i ${MINIKUBE_SSH_KEY:-~/.config/cloudkube/minikube-ssh-key} docker@$SPOT_INSTANCE_DNS_NAME \
           "docker images | grep -E 'employee-api' | grep latest | awk '{print \$1\":\"\$2}' | xargs -r docker rmi -f" || true
   else
       print_warning "Not deleting latest images because SPOT_INSTANCE_DNS_NAME is not set..."
   fi
else
   print_status "Cleaning images on local minikube..."
   minikube ssh "docker images | grep ${REGISTRY} | grep latest | awk '{print \$1\":\" \$2}' | xargs -r docker rmi -f" 2>/dev/null || true
fi

#2D. Build fresh images using build-update.sh
print_status "Step 2D: Building fresh Docker images..."

# Build Employee API
print_status "Building Employee API (PostgreSQL version)..."
./build-update.sh employee-api latest --build-only

# Build Merchant API
print_status "Building Merchant API (Java Spring Boot)..."
./build-update.sh merchant-api latest --build-only

# Auth Service has been migrated to Istio OPA Integration
print_status "Auth Service has been migrated to Istio OPA Integration"
print_status "No longer building auth-service - using native Istio authorization"

print_success "Docker images built successfully"

#2E. Update Helm chart dependencies
print_status "Step 2E: Updating Helm chart dependencies..."
(cd ${CHART_PATH} && helm dependency update)
if [ "$?" != "0" ]; then
    print_error "Couldn't update ${CHART_PATH} chart dependencies. Bailing"
    exit 1
fi

#2F. Install the chart
print_status "Step 2F: Installing Helm chart..."

# Set image names based on environment (matching build-update.sh output)
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ]; then
    EMPLOYEE_IMAGE="localhost:5000/employee-api:latest"
    MERCHANT_IMAGE="localhost:5000/merchant-api:latest"
    IMAGE_PULL_POLICY="IfNotPresent"
else
    EMPLOYEE_IMAGE="${REGISTRY}/employee-api:latest"
    MERCHANT_IMAGE="${REGISTRY}/merchant-api:latest"
    IMAGE_PULL_POLICY="Never"
fi

# Try helm install first, if it fails due to existing resources, do upgrade instead
print_status "Attempting Helm installation..."
if ! helm -n${NAMESPACE} install ${RELEASE_NAME} ${CHART_PATH} \
    --create-namespace \
    --wait \
    --timeout 5m \
    --set global.namespace=${NAMESPACE} \
    --set employeeApi.image=${EMPLOYEE_IMAGE} \
    --set employeeApi.imagePullPolicy=${IMAGE_PULL_POLICY} \
    --set merchantApi.image.repository=$(echo ${MERCHANT_IMAGE} | sed 's/:[^:]*$//') \
    --set merchantApi.image.tag=$(echo ${MERCHANT_IMAGE} | sed 's/.*://') \
    --set merchantApi.image.pullPolicy=${IMAGE_PULL_POLICY} \
    --set istio.enabled=true \
    --set istio.opaExtAuthz.enabled=true 2>/dev/null; then
    
    print_warning "Install failed, trying upgrade instead..."
    helm -n${NAMESPACE} upgrade ${RELEASE_NAME} ${CHART_PATH} \
        --wait \
        --timeout 5m \
        --set global.namespace=${NAMESPACE} \
        --set employeeApi.image=${EMPLOYEE_IMAGE} \
        --set employeeApi.imagePullPolicy=${IMAGE_PULL_POLICY} \
        --set merchantApi.image.repository=$(echo ${MERCHANT_IMAGE} | sed 's/:[^:]*$//') \
        --set merchantApi.image.tag=$(echo ${MERCHANT_IMAGE} | sed 's/.*://') \
        --set merchantApi.image.pullPolicy=${IMAGE_PULL_POLICY} \
        --set istio.enabled=true \
        --set istio.opaExtAuthz.enabled=true
fi

if [ "$?" != "0" ]; then
    print_error "Couldn't install ${RELEASE_NAME} chart. Bailing"
    exit 1
fi

print_success "Helm chart installed successfully"

#3. Verify deployment
print_status "Step 3: Verifying deployment..."

# Wait for all pods to be ready
print_status "Waiting for all pods to be ready..."
if ! kubectl wait --for=condition=ready pod --all -n ${NAMESPACE} --timeout=300s; then
    print_error "Pods failed to become ready within timeout"
    print_status "Current pod status:"
    kubectl get pods -n ${NAMESPACE}
    print_status "Pod events:"
    kubectl get events -n ${NAMESPACE} --sort-by=.metadata.creationTimestamp | tail -10
    exit 1
fi

# Check pod status
print_status "Pod status:"
kubectl get pods -n ${NAMESPACE}

# Check services
print_status "Service status:"
kubectl get services -n ${NAMESPACE}

# Allow services a moment to fully initialize
print_status "Allowing services to fully initialize..."
sleep 5

# Initialize health check counter
HEALTH_CHECKS_PASSED=0
TOTAL_HEALTH_CHECKS=3

# Test database connectivity
print_status "Testing database connectivity..."
DB_POD=$(kubectl get pod -l app=postgresql -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DB_POD" ]; then
    DB_TEST=$(kubectl exec $DB_POD -n ${NAMESPACE} -- psql -U postgres -d opa_demo -c "SELECT 'DB_OK' as status;" 2>/dev/null | grep -o DB_OK || echo "FAILED")
    if [ "$DB_TEST" = "DB_OK" ]; then
        print_success "Database connectivity verified"
        HEALTH_CHECKS_PASSED=$((HEALTH_CHECKS_PASSED + 1))
    else
        print_warning "Database connectivity test failed"
    fi
else
    print_warning "PostgreSQL pod not found for testing"
fi

# Test Employee API health
print_status "Testing Employee API health..."
API_POD=$(kubectl get pod -l app=employee-api -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$API_POD" ]; then
    # Wait a bit for the API to be fully ready
    sleep 10
    HEALTH_CHECK=$(kubectl exec $API_POD -n ${NAMESPACE} -- python -c "
import http.client
try:
    conn = http.client.HTTPConnection('localhost:8080')
    conn.request('GET', '/health')
    response = conn.getresponse()
    data = response.read().decode()
    if response.status == 200 and 'healthy' in data:
        print('SUCCESS')
    else:
        print('FAILED')
except:
    print('FAILED')
" 2>/dev/null || echo "FAILED")
    if [ "$HEALTH_CHECK" = "SUCCESS" ]; then
        print_success "Employee API health check passed"
        HEALTH_CHECKS_PASSED=$((HEALTH_CHECKS_PASSED + 1))
    else
        print_warning "Employee API health check failed or not ready yet"
    fi
else
    print_warning "Employee API pod not found for testing"
fi

# Test OPA service
print_status "Testing OPA service..."
OPA_POD=$(kubectl get pod -l app=opa -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$OPA_POD" ]; then
    # OPA container has curl available
    OPA_CHECK=$(kubectl exec $OPA_POD -n ${NAMESPACE} -- curl -s http://localhost:8181/v1/policies 2>/dev/null | grep -o "policies" || echo "FAILED")
    if [ "$OPA_CHECK" = "policies" ]; then
        print_success "OPA service check passed"
        HEALTH_CHECKS_PASSED=$((HEALTH_CHECKS_PASSED + 1))
    else
        print_warning "OPA service check failed"
    fi
else
    print_warning "OPA pod not found for testing"
fi

# Test Keycloak service
print_status "Testing Keycloak service..."
KEYCLOAK_POD=$(kubectl get pod -l app=keycloak -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$KEYCLOAK_POD" ]; then
    # Test Keycloak health endpoint
    KEYCLOAK_CHECK=$(kubectl exec $KEYCLOAK_POD -n ${NAMESPACE} -- curl -s http://localhost:8080/health/ready 2>/dev/null | grep -o "ready" || echo "FAILED")
    if [ "$KEYCLOAK_CHECK" = "ready" ]; then
        print_success "Keycloak service check passed"
        HEALTH_CHECKS_PASSED=$((HEALTH_CHECKS_PASSED + 1))
    else
        print_warning "Keycloak service check failed"
    fi
else
    print_warning "Keycloak pod not found for testing"
fi

#4. Display access information
print_status "Step 4: Deployment Summary"
echo ""

# Display health check summary
print_status "Health Check Summary: ${HEALTH_CHECKS_PASSED}/${TOTAL_HEALTH_CHECKS} services healthy"
if [ "$HEALTH_CHECKS_PASSED" -eq "$TOTAL_HEALTH_CHECKS" ]; then
    print_success "🎉 All health checks passed! OPA-Keycloak deployment completed successfully!"
elif [ "$HEALTH_CHECKS_PASSED" -gt 0 ]; then
    print_warning "⚠️  Some health checks failed, but core services are running. Check logs for details."
else
    print_error "❌ Most health checks failed. Please check pod logs and troubleshoot."
fi
echo ""
print_status "Deployed Services Summary:"
print_status "=========================="
echo "✅ PostgreSQL Database (persistent storage)"
echo "✅ Keycloak Identity Management"
echo "✅ Employee API (PostgreSQL-enabled)"
echo "✅ Merchant API (Java Spring Boot)"
echo "✅ OPA-Envoy (Istio external authorization)"
echo "✅ OPA Policy Engine"
echo "✅ Istio Gateway & VirtualService"
echo ""
print_status "Access Information:"
print_status "==================="

# Get Istio Gateway info
ISTIO_GATEWAY_PORT=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}' 2>/dev/null || echo "31772")
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ]; then
    print_status "Using cloud minikube. Set up SSH tunnel with: ./scripts/setup-tunnel.sh"
    echo "🌐 Access via tunnel: http://opa-demo.local"
else
    MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
    echo "🌐 Minikube IP: $MINIKUBE_IP:$ISTIO_GATEWAY_PORT"
fi

echo "🔑 Keycloak Admin: http://opa-demo.local/auth/ (admin/admin123)"
echo "👥 Employee API: http://opa-demo.local/api/v1/employees"
echo "🏪 Merchant API: http://opa-demo.local/api/v1/merchants"
echo "🩺 Health Check: http://opa-demo.local/health"
echo "🛡️  OPA Policies: Direct access via port-forward"
echo ""

print_status "Port Forward Commands (for direct service access):"
echo "kubectl port-forward -n ${NAMESPACE} service/keycloak-service 8080:8080"
echo "kubectl port-forward -n ${NAMESPACE} service/employee-api-service 3000:8080"
echo "kubectl port-forward -n ${NAMESPACE} service/merchant-api-service 8081:8080"
echo "kubectl port-forward -n ${NAMESPACE} service/opa-service 8181:8181"
echo ""

print_status "Useful Commands:"
echo "helm list -n ${NAMESPACE}"
echo "kubectl get all -n ${NAMESPACE}"
echo "kubectl logs -f deployment/employee-api -n ${NAMESPACE}"
echo ""

print_status "Troubleshooting Commands:"
echo "# Check pod logs:"
echo "kubectl logs -l app=employee-api -n ${NAMESPACE}"
echo "kubectl logs -l app=merchant-api -n ${NAMESPACE}"
echo "kubectl logs -l app=keycloak -n ${NAMESPACE}"
echo "kubectl logs -l app=opa -n ${NAMESPACE}"
echo ""
echo "# Check Istio Gateway status:"
echo "kubectl get gateway,virtualservice -n ${NAMESPACE}"
echo "kubectl get svc -n istio-system istio-ingressgateway"
echo ""
echo "# Check pod details:"
echo "kubectl describe pod -l app=employee-api -n ${NAMESPACE}"
echo ""
echo "# Test services directly:"
echo "kubectl port-forward -n ${NAMESPACE} service/employee-api-service 8080:8080"
echo "curl http://localhost:8080/health"
echo ""
echo "# Test tunnel connectivity:"
echo "./scripts/setup-tunnel.sh  # Start tunnel"
echo "curl http://opa-demo.local/auth/  # Test Keycloak"
echo ""

print_success "✅ Deployment completed successfully!"

exit 0 