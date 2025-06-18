#!/bin/bash
set -e
set -x

# OPA-Keycloak Clean Helm Deployment Script
# Based on proven HQ deployment patterns
# Handles complete lifecycle: cleanup, build, deploy, verify

helm >/dev/null 2>&1 || { echo "Need to install helm v3.8+ "; exit 1; }

# Configuration
NAMESPACE="opa-keycloak"
RELEASE_NAME="opa-keycloak"
CHART_PATH="./helm/opa-keycloak-postgres"
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
kubectl delete configmap kong-declarative-config -n default 2>/dev/null || true
kubectl delete configmap kong-declarative-config -n ${NAMESPACE} 2>/dev/null || true
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
kubectl delete ingress opa-demo-kong -n default 2>/dev/null || true
kubectl delete ingress opa-demo-kong -n ${NAMESPACE} 2>/dev/null || true

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
           "docker images | grep -E '(employee-api|auth-service)' | grep latest | awk '{print \$1\":\"\$2}' | xargs -r docker rmi -f" || true
   else
       print_warning "Not deleting latest images because SPOT_INSTANCE_DNS_NAME is not set..."
   fi
else
   print_status "Cleaning images on local minikube..."
   minikube ssh "docker images | grep ${REGISTRY} | grep latest | awk '{print \$1\":\" \$2}' | xargs -r docker rmi -f" 2>/dev/null || true
fi

#2D. Build fresh images
print_status "Step 2D: Building fresh Docker images..."

# Build Employee API
print_status "Building Employee API (PostgreSQL version)..."
cd apps/employee-api
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    eval $(ssh-agent)
    MINIKUBE_SSH_KEY=${MINIKUBE_SSH_KEY:-~/.config/cloudkube/minikube-ssh-key}
    ssh-add $MINIKUBE_SSH_KEY
    docker -H ssh://docker@$SPOT_INSTANCE_DNS_NAME:2222 build -f Dockerfile-postgres -t employee-api:latest .
    eval $(ssh-agent -k)
else
    eval $(minikube docker-env)
    docker build -f Dockerfile-postgres -t ${REGISTRY}/employee-api:latest .
fi
cd ../..

# Build Auth Service
print_status "Building Auth Service..."
cd apps/auth-service
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    eval $(ssh-agent)
    MINIKUBE_SSH_KEY=${MINIKUBE_SSH_KEY:-~/.config/cloudkube/minikube-ssh-key}
    ssh-add $MINIKUBE_SSH_KEY
    docker -H ssh://docker@$SPOT_INSTANCE_DNS_NAME:2222 build -t auth-service:latest .
    eval $(ssh-agent -k)
else
    eval $(minikube docker-env)
    docker build -t ${REGISTRY}/auth-service:latest .
fi
cd ../..

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

# For cloud minikube, don't use registry prefix since images are built directly in minikube
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ]; then
    EMPLOYEE_IMAGE="employee-api:latest"
    AUTH_IMAGE="auth-service:latest"
else
    EMPLOYEE_IMAGE="${REGISTRY}/employee-api:latest"
    AUTH_IMAGE="${REGISTRY}/auth-service:latest"
fi

helm -n${NAMESPACE} install ${RELEASE_NAME} ${CHART_PATH} \
    --create-namespace \
    --wait \
    --timeout 3m \
    --set global.namespace=${NAMESPACE} \
    --set employeeApi.image=${EMPLOYEE_IMAGE} \
    --set employeeApi.imagePullPolicy=Never \
    --set authService.image=${AUTH_IMAGE} \
    --set authService.imagePullPolicy=Never

if [ "$?" != "0" ]; then
    print_error "Couldn't install ${RELEASE_NAME} chart. Bailing"
    exit 1
fi

print_success "Helm chart installed successfully"

#3. Verify deployment
print_status "Step 3: Verifying deployment..."

# Wait for all pods to be ready
print_status "Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod --all -n ${NAMESPACE} --timeout=300s

# Check pod status
print_status "Pod status:"
kubectl get pods -n ${NAMESPACE}

# Check services
print_status "Service status:"
kubectl get services -n ${NAMESPACE}

# Test database connectivity
print_status "Testing database connectivity..."
DB_POD=$(kubectl get pod -l app=postgresql -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DB_POD" ]; then
    DB_TEST=$(kubectl exec $DB_POD -n ${NAMESPACE} -- psql -U postgres -d opa_demo -c "SELECT 'DB_OK' as status;" 2>/dev/null | grep DB_OK || echo "FAILED")
    if [ "$DB_TEST" = "DB_OK" ]; then
        print_success "Database connectivity verified"
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
    HEALTH_CHECK=$(kubectl exec $API_POD -n ${NAMESPACE} -- curl -s http://localhost:8080/health 2>/dev/null | grep -o '"status":"healthy"' || echo "FAILED")
    if [ "$HEALTH_CHECK" != "FAILED" ]; then
        print_success "Employee API health check passed"
    else
        print_warning "Employee API health check failed or not ready yet"
    fi
else
    print_warning "Employee API pod not found for testing"
fi

#4. Display access information
print_status "Step 4: Deployment Summary"
echo ""
print_success "🎉 OPA-Keycloak deployment completed successfully!"
echo ""
print_status "Access Information:"
print_status "==================="

# Get ingress info
INGRESS_IP=$(kubectl get ingress -n ${NAMESPACE} -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
if [ "$INGRESS_IP" = "pending" ] || [ -z "$INGRESS_IP" ]; then
    INGRESS_IP=$(minikube ip 2>/dev/null || echo "localhost")
fi

echo "🌐 Ingress IP: $INGRESS_IP"
echo "🔑 Keycloak Admin: http://$INGRESS_IP/keycloak (admin/admin123)"
echo "👥 Employee API: http://$INGRESS_IP/api/employees"
echo "🛡️  OPA Policies: http://$INGRESS_IP:8181/v1/policies"
echo "🚀 Kong Gateway: http://$INGRESS_IP:8000"
echo ""

print_status "Port Forward Commands (if ingress not working):"
echo "kubectl port-forward -n ${NAMESPACE} service/keycloak-service 8080:8080"
echo "kubectl port-forward -n ${NAMESPACE} service/employee-api-service 3000:8080"
echo "kubectl port-forward -n ${NAMESPACE} service/opa-service 8181:8181"
echo ""

print_status "Useful Commands:"
echo "helm list -n ${NAMESPACE}"
echo "kubectl get all -n ${NAMESPACE}"
echo "kubectl logs -f deployment/employee-api -n ${NAMESPACE}"
echo ""

print_success "✅ Deployment completed successfully!"

exit 0 