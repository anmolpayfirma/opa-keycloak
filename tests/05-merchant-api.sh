#!/bin/bash

# Merchant API Test
# Tests merchant-api integration with Istio Gateway and OPA authorization

set -e

echo "🔧 Merchant API Test (via Istio Gateway)"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test configuration
GATEWAY_HOST="opa-demo.local"
BASE_URL="http://localhost"
API_URL="$BASE_URL/api/v1/merchants"
HEALTH_URL="$BASE_URL/api/v1/merchants/health"

# Check if API is accessible
print_status "Checking merchant-api health endpoint..."
if curl -s --connect-timeout 5 -H "Host: $GATEWAY_HOST" "$HEALTH_URL" > /dev/null; then
    print_success "✅ Merchant API health endpoint is accessible"
else
    print_error "❌ Merchant API health endpoint not accessible"
    echo "   Make sure merchant-api is deployed and SSH tunnel is active"
    exit 1
fi

# Test unauthorized access
print_status "Testing unauthorized access..."
UNAUTH_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null -H "Host: $GATEWAY_HOST" "$API_URL")

if [ "$UNAUTH_RESPONSE" = "403" ]; then
    print_success "✅ Unauthorized access properly denied (HTTP 403)"
else
    print_error "❌ Expected 403 for unauthorized access, got HTTP $UNAUTH_RESPONSE"
fi

# Test with authentication (if tokens are available)
if [ -n "$EMPLOYEE_TOKEN" ]; then
    print_status "Testing employee access..."
    
    # Test GET request
    EMPLOYEE_GET=$(curl -s -w "%{http_code}" -o /dev/null -H "Host: $GATEWAY_HOST" -H "Authorization: Bearer $EMPLOYEE_TOKEN" "$API_URL")
    
    if [ "$EMPLOYEE_GET" = "200" ]; then
        print_success "✅ Employee GET access allowed (HTTP 200)"
    else
        print_error "❌ Employee GET access failed (HTTP $EMPLOYEE_GET)"
    fi
    
    # Test POST request (should be denied for CRUD template)
    EMPLOYEE_POST=$(curl -s -w "%{http_code}" -o /dev/null -X POST -H "Host: $GATEWAY_HOST" -H "Authorization: Bearer $EMPLOYEE_TOKEN" -H "Content-Type: application/json" -d '{"name":"Test"}' "$API_URL")
    
    if [ "$EMPLOYEE_POST" = "403" ]; then
        print_success "✅ Employee POST access properly denied (HTTP 403)"
    else
        print_error "❌ Expected 403 for employee POST, got HTTP $EMPLOYEE_POST"
    fi
fi

if [ -n "$MANAGER_TOKEN" ]; then
    print_status "Testing manager access..."
    
    # Test GET request
    MANAGER_GET=$(curl -s -w "%{http_code}" -o /dev/null -H "Host: $GATEWAY_HOST" -H "Authorization: Bearer $MANAGER_TOKEN" "$API_URL")
    
    if [ "$MANAGER_GET" = "200" ]; then
        print_success "✅ Manager GET access allowed (HTTP 200)"
    else
        print_error "❌ Manager GET access failed (HTTP $MANAGER_GET)"
    fi
    
    # Test POST request
    MANAGER_POST=$(curl -s -w "%{http_code}" -o /dev/null -X POST -H "Host: $GATEWAY_HOST" -H "Authorization: Bearer $MANAGER_TOKEN" -H "Content-Type: application/json" -d '{"name":"Test Manager Create"}' "$API_URL")
    
    if [ "$MANAGER_POST" = "201" ] || [ "$MANAGER_POST" = "200" ] || [ "$MANAGER_POST" = "400" ]; then
        print_success "✅ Manager POST access allowed (HTTP $MANAGER_POST)"
    else
        print_error "❌ Manager POST access failed (HTTP $MANAGER_POST)"
    fi
fi

print_status "📊 Merchant API Test Summary"
echo "================================="
print_success "✅ Merchant API integration test completed"

echo ""
echo "🎯 Merchant API Test Complete"
echo "=================================================="
