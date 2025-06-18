#!/bin/bash

# Master Test Runner
# Runs all tests in sequence with proper port forwarding setup

set -e

echo "🧪 OPA-Keycloak Test Suite"
echo "=========================="

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

# Cleanup function
cleanup() {
    print_status "Cleaning up port forwards..."
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 2
}

# Set up cleanup trap
trap cleanup EXIT

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

# Check if services are running
print_status "Checking if services are deployed..."
if ! kubectl get pods -n opa-keycloak >/dev/null 2>&1; then
    print_error "❌ Services not found in opa-keycloak namespace"
    echo "   Run: ./scripts/helm-deploy-clean.sh to deploy services"
    exit 1
fi

# Get pod status
PODS_STATUS=$(kubectl get pods -n opa-keycloak --no-headers)
if echo "$PODS_STATUS" | grep -v "Running" | grep -v "Completed" >/dev/null; then
    print_warning "⚠️  Some pods are not running:"
    echo "$PODS_STATUS"
    echo ""
fi

# Set up port forwarding
print_status "Setting up port forwarding..."

# Kill any existing port forwards
cleanup

# Start port forwards in background
kubectl port-forward service/employee-api-service 3000:8080 -n opa-keycloak >/dev/null 2>&1 &
EMPLOYEE_API_PF_PID=$!

kubectl port-forward service/keycloak-service 8082:8080 -n opa-keycloak >/dev/null 2>&1 &
KEYCLOAK_PF_PID=$!

kubectl port-forward service/auth-service 8081:80 -n opa-keycloak >/dev/null 2>&1 &
AUTH_SERVICE_PF_PID=$!

# Wait for port forwards to establish
print_status "Waiting for port forwards to establish..."
sleep 5

# Verify port forwards are working
if ! curl -s --connect-timeout 5 http://localhost:3000/health >/dev/null; then
    print_error "❌ Employee API port forward failed"
    exit 1
fi

if ! curl -s --connect-timeout 5 http://localhost:8082/health >/dev/null; then
    print_error "❌ Keycloak port forward failed"
    exit 1
fi

print_success "✅ Port forwarding established"
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