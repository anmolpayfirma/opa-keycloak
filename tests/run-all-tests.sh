#!/bin/bash

# Master Test Runner
# Runs all tests in sequence using Istio Gateway

set -e

echo "🧪 OPA-Keycloak Test Suite (via Istio Gateway)"
echo "=============================================="

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

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    print_error "❌ kubectl not found. Please install kubectl."
    exit 1
fi

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
    print_error "❌ jq not found. Please install jq."
    exit 1
fi

# Check if curl is available
if ! command -v curl >/dev/null 2>&1; then
    print_error "❌ curl not found. Please install curl."
    exit 1
fi

# Check if services are running
print_status "Checking if services are deployed..."
if ! kubectl get pods -n opa-keycloak >/dev/null 2>&1; then
    print_error "❌ Services not found in opa-keycloak namespace"
    echo "   Run: ./scripts/helm-deploy-istio.sh to deploy services"
    exit 1
fi

# Get pod status
PODS_STATUS=$(kubectl get pods -n opa-keycloak --no-headers)
if echo "$PODS_STATUS" | grep -v "Running" | grep -v "Completed" >/dev/null; then
    print_warning "⚠️  Some pods are not running:"
    echo "$PODS_STATUS"
    echo ""
fi

# Check if Istio Gateway is configured
print_status "Checking Istio Gateway configuration..."
if ! kubectl get gateway -n opa-keycloak opa-demo-gateway >/dev/null 2>&1; then
    print_error "❌ Istio Gateway not found"
    echo "   Run: helm upgrade opa-keycloak helm/opa-keycloak --namespace opa-keycloak"
    exit 1
fi

if ! kubectl get virtualservice -n opa-keycloak opa-demo-vs >/dev/null 2>&1; then
    print_error "❌ Istio VirtualService not found"
    echo "   Run: helm upgrade opa-keycloak helm/opa-keycloak --namespace opa-keycloak"
    exit 1
fi

print_success "✅ Istio Gateway and VirtualService are configured"

# Check if SSH tunnel is active
print_status "Checking SSH tunnel connectivity..."
if ! curl -s --connect-timeout 5 -H "Host: opa-demo.local" http://localhost/health >/dev/null 2>&1; then
    print_error "❌ Cannot reach services through Istio Gateway"
    echo "   Make sure SSH tunnel is active:"
    echo "   ./scripts/setup-tunnel.sh"
    echo ""
    echo "   Or check if /etc/hosts contains:"
    echo "   127.0.0.1 opa-demo.local"
    exit 1
fi

print_success "✅ Istio Gateway is accessible through SSH tunnel"
echo ""

# Test directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Make test scripts executable
chmod +x "$TEST_DIR"/*.sh

# Run tests in sequence
TESTS=(
    "01-basic-connectivity.sh"
    "02-employee-crud.sh"
    "03-authentication.sh"
    "05-merchant-service.sh"
)

PASSED=0
FAILED=0

for test in "${TESTS[@]}"; do
    TEST_PATH="$TEST_DIR/$test"
    
    if [ -f "$TEST_PATH" ]; then
        echo ""
        echo "🔄 Running $test..."
        echo "$(printf '=%.0s' {1..50})"
        
        if bash "$TEST_PATH"; then
            print_success "✅ $test PASSED"
            ((PASSED++))
        else
            print_error "❌ $test FAILED"
            ((FAILED++))
        fi
        
        echo ""
        echo "$(printf '=%.0s' {1..50})"
    else
        print_warning "⚠️  Test file $test not found"
    fi
done

# Summary
echo ""
echo "📊 Test Summary"
echo "==============="
echo "Total tests: $((PASSED + FAILED))"
print_success "Passed: $PASSED"
if [ $FAILED -gt 0 ]; then
    print_error "Failed: $FAILED"
else
    print_success "Failed: $FAILED"
fi

echo ""
if [ $FAILED -eq 0 ]; then
    print_success "🎉 All tests passed!"
    exit 0
else
    print_error "💥 Some tests failed!"
    exit 1
fi 
