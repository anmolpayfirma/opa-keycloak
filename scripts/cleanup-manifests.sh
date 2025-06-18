#!/bin/bash

# Cleanup Script for Legacy Kubernetes Manifests
# Use this to clean up loose manifests before moving to Helm-only deployment

set -e

NAMESPACE="opa-keycloak-practice"
LEGACY_NAMESPACE="default"

echo "🧹 Cleaning up legacy Kubernetes manifests..."
echo "============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Function to safely delete resources
safe_delete() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    
    if kubectl get $resource_type $resource_name -n $namespace >/dev/null 2>&1; then
        print_status "Deleting $resource_type/$resource_name from namespace $namespace"
        kubectl delete $resource_type $resource_name -n $namespace
    else
        print_status "$resource_type/$resource_name not found in namespace $namespace (already deleted)"
    fi
}

# Clean up resources in the legacy practice namespace
print_status "Cleaning up resources in namespace: $NAMESPACE"

# Deployments
safe_delete "deployment" "employee-api" "$NAMESPACE"
safe_delete "deployment" "auth-service" "$NAMESPACE"
safe_delete "deployment" "keycloak" "$NAMESPACE"
safe_delete "deployment" "opa" "$NAMESPACE"
safe_delete "deployment" "kong-gateway" "$NAMESPACE"
safe_delete "deployment" "postgresql" "$NAMESPACE"

# Services
safe_delete "service" "employee-api-service" "$NAMESPACE"
safe_delete "service" "auth-service" "$NAMESPACE"
safe_delete "service" "keycloak-service" "$NAMESPACE"
safe_delete "service" "opa-service" "$NAMESPACE"
safe_delete "service" "kong-service" "$NAMESPACE"
safe_delete "service" "kong-admin-service" "$NAMESPACE"
safe_delete "service" "postgresql-service" "$NAMESPACE"

# ConfigMaps
safe_delete "configmap" "opa-policies" "$NAMESPACE"
safe_delete "configmap" "keycloak-config" "$NAMESPACE"
safe_delete "configmap" "kong-config" "$NAMESPACE"
safe_delete "configmap" "kong-declarative-config" "$NAMESPACE"
safe_delete "configmap" "kong-declarative-config" "$LEGACY_NAMESPACE"

# Secrets
safe_delete "secret" "postgresql-secret" "$NAMESPACE"
safe_delete "secret" "keycloak-secret" "$NAMESPACE"

# PVCs
safe_delete "pvc" "postgresql-pvc" "$NAMESPACE"
safe_delete "pvc" "keycloak-pvc" "$NAMESPACE"

# Ingress
safe_delete "ingress" "opa-keycloak-ingress" "$NAMESPACE"
safe_delete "ingress" "kong-ingress" "$NAMESPACE"

# Clean up any resources in default namespace too
print_status "Cleaning up any resources in default namespace: $LEGACY_NAMESPACE"

safe_delete "deployment" "employee-api" "$LEGACY_NAMESPACE"
safe_delete "deployment" "auth-service" "$LEGACY_NAMESPACE"
safe_delete "deployment" "keycloak" "$LEGACY_NAMESPACE"
safe_delete "deployment" "opa" "$LEGACY_NAMESPACE"
safe_delete "deployment" "kong-gateway" "$LEGACY_NAMESPACE"
safe_delete "deployment" "postgresql" "$LEGACY_NAMESPACE"

safe_delete "service" "employee-api-service" "$LEGACY_NAMESPACE"
safe_delete "service" "auth-service" "$LEGACY_NAMESPACE"
safe_delete "service" "keycloak-service" "$LEGACY_NAMESPACE"
safe_delete "service" "opa-service" "$LEGACY_NAMESPACE"
safe_delete "service" "kong-service" "$LEGACY_NAMESPACE"
safe_delete "service" "kong-admin-service" "$LEGACY_NAMESPACE"
safe_delete "service" "postgresql-service" "$LEGACY_NAMESPACE"

# Check for any remaining resources
print_status "Checking for any remaining resources..."

echo ""
print_status "Remaining deployments in $NAMESPACE:"
kubectl get deployments -n $NAMESPACE 2>/dev/null || echo "No deployments found"

echo ""
print_status "Remaining services in $NAMESPACE:"
kubectl get services -n $NAMESPACE 2>/dev/null || echo "No services found"

echo ""
print_status "Remaining PVCs in $NAMESPACE:"
kubectl get pvc -n $NAMESPACE 2>/dev/null || echo "No PVCs found"

echo ""
print_success "✅ Legacy manifest cleanup completed!"
print_status "Now you can use the new Helm-based deployment:"
print_status "  ./scripts/helm-deploy-clean.sh"

echo ""
print_warning "Note: If you want to completely remove the namespace, run:"
print_warning "  kubectl delete namespace $NAMESPACE"
print_warning "  kubectl delete namespace $LEGACY_NAMESPACE" 