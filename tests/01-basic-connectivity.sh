#!/bin/bash

# Basic Connectivity Test
# Tests if all services are accessible via Istio Gateway

set -e

echo "🔗 Basic Connectivity Test (via Istio Gateway)"
echo "==============================================="

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

# Test configuration - Using Istio Gateway via localhost with Host header
GATEWAY_HOST="opa-demo.local"
BASE_URL="http://localhost"
HEALTH_URL="$BASE_URL/health"
KEYCLOAK_URL="$BASE_URL/auth"
EMPLOYEE_API_URL="$BASE_URL/api/v1/employees"
OPA_URL="$BASE_URL/opa"

echo ""
print_status "Testing service connectivity through Istio Gateway..."

# Test Health Endpoint
print_status "1. Testing Health endpoint at $HEALTH_URL"
if curl -s --connect-timeout 5 -H "Host: $GATEWAY_HOST" "$HEALTH_URL" > /dev/null; then
    HEALTH_RESPONSE=$(curl -s -H "Host: $GATEWAY_HOST" "$HEALTH_URL")
    if echo "$HEALTH_RESPONSE" | grep -q '"status": "healthy"'; then
        print_success "✅ Health endpoint is responding"
        echo "   Status: $(echo "$HEALTH_RESPONSE" | jq -r '.status')"
        echo "   Service: $(echo "$HEALTH_RESPONSE" | jq -r '.service')"
        echo "   Database: $(echo "$HEALTH_RESPONSE" | jq -r '.database')"
    else
        print_warning "⚠️  Health endpoint responded but may have issues"
        echo "   Response: $HEALTH_RESPONSE"
    fi
else
    print_error "❌ Health endpoint is not accessible"
    echo "   Make sure SSH tunnel is active: ./scripts/setup-tunnel.sh"
    echo "   And /etc/hosts contains: 127.0.0.1 opa-demo.local"
fi

echo ""

# Test Keycloak
print_status "2. Testing Keycloak at $KEYCLOAK_URL"
if curl -s --connect-timeout 5 -H "Host: $GATEWAY_HOST" "$KEYCLOAK_URL/health" > /dev/null; then
    KEYCLOAK_HEALTH=$(curl -s -H "Host: $GATEWAY_HOST" "$KEYCLOAK_URL/health")
    if echo "$KEYCLOAK_HEALTH" | grep -q '"status": "UP"'; then
        print_success "✅ Keycloak is healthy"
        echo "   Status: $(echo "$KEYCLOAK_HEALTH" | jq -r '.status')"
    else
        print_warning "⚠️  Keycloak responded but may have issues"
        echo "   Response: $KEYCLOAK_HEALTH"
    fi
else
    print_error "❌ Keycloak is not accessible"
    echo "   Check Istio routing configuration"
fi

# Test Keycloak admin console access
print_status "2a. Testing Keycloak admin console access"
ADMIN_RESPONSE=$(curl -s -I -H "Host: $GATEWAY_HOST" "$KEYCLOAK_URL/admin/" | head -n 1)
if echo "$ADMIN_RESPONSE" | grep -q "302\|200"; then
    print_success "✅ Keycloak admin console is accessible"
    echo "   Response: $ADMIN_RESPONSE"
else
    print_error "❌ Keycloak admin console not accessible"
    echo "   Response: $ADMIN_RESPONSE"
fi

echo ""

# Test Employee API
print_status "3. Testing Employee API at $EMPLOYEE_API_URL"
EMPLOYEE_RESPONSE=$(curl -s -w "%{http_code}" -H "Host: $GATEWAY_HOST" "$EMPLOYEE_API_URL" -o /tmp/employee_test_response 2>/dev/null)
EMPLOYEE_BODY=$(cat /tmp/employee_test_response 2>/dev/null || echo "")

if [ "$EMPLOYEE_RESPONSE" = "501" ]; then
    print_success "✅ Employee API is accessible (returns 501 as expected for unauthenticated requests)"
    echo "   HTTP Status: $EMPLOYEE_RESPONSE"
elif [ "$EMPLOYEE_RESPONSE" = "401" ]; then
    print_success "✅ Employee API is accessible (returns 401 as expected for unauthenticated requests)"
    echo "   HTTP Status: $EMPLOYEE_RESPONSE"
elif [ "$EMPLOYEE_RESPONSE" = "200" ]; then
    print_success "✅ Employee API is accessible and returning data"
    echo "   HTTP Status: $EMPLOYEE_RESPONSE"
    if echo "$EMPLOYEE_BODY" | jq -e '.count' >/dev/null 2>&1; then
        EMPLOYEE_COUNT=$(echo "$EMPLOYEE_BODY" | jq -r '.count')
        echo "   Found $EMPLOYEE_COUNT employees"
    fi
else
    print_error "❌ Employee API returned unexpected status: $EMPLOYEE_RESPONSE"
    echo "   Response body: $EMPLOYEE_BODY"
fi

# Clean up temp file
rm -f /tmp/employee_test_response

echo ""

# Test OPA
print_status "4. Testing OPA at $OPA_URL"
OPA_RESPONSE=$(curl -s -w "%{http_code}" -H "Host: $GATEWAY_HOST" "$OPA_URL/v1/data" -o /tmp/opa_test_response 2>/dev/null)
OPA_BODY=$(cat /tmp/opa_test_response 2>/dev/null || echo "")

if [ "$OPA_RESPONSE" = "200" ]; then
    print_success "✅ OPA is accessible and responding"
    echo "   HTTP Status: $OPA_RESPONSE"
    if echo "$OPA_BODY" | jq -e '.result' >/dev/null 2>&1; then
        echo "   OPA data structure is valid"
    fi
elif [ "$OPA_RESPONSE" = "301" ]; then
    print_success "✅ OPA is accessible (redirect as expected)"
    echo "   HTTP Status: $OPA_RESPONSE (redirect)"
else
    print_error "❌ OPA returned unexpected status: $OPA_RESPONSE"
    echo "   Response body: $OPA_BODY"
fi

# Clean up temp file
rm -f /tmp/opa_test_response

echo ""

# Test Keycloak realm
print_status "5. Testing Keycloak realm configuration"
if curl -s --connect-timeout 5 -H "Host: $GATEWAY_HOST" "$KEYCLOAK_URL/realms/employee-management/.well-known/openid_configuration" > /dev/null; then
    REALM_CONFIG=$(curl -s -H "Host: $GATEWAY_HOST" "$KEYCLOAK_URL/realms/employee-management/.well-known/openid_configuration")
    if echo "$REALM_CONFIG" | jq -e '.issuer' > /dev/null 2>&1; then
        print_success "✅ Employee-management realm is configured"
        echo "   Issuer: $(echo "$REALM_CONFIG" | jq -r '.issuer')"
        echo "   Token endpoint: $(echo "$REALM_CONFIG" | jq -r '.token_endpoint')"
        echo "   Auth endpoint: $(echo "$REALM_CONFIG" | jq -r '.authorization_endpoint')"
    else
        print_warning "⚠️  Realm exists but configuration may be incomplete"
    fi
else
    print_error "❌ Employee-management realm not found"
    echo "   Run: ./scripts/setup-keycloak.sh to configure Keycloak"
fi

echo ""

# Test Istio Gateway configuration
print_status "6. Testing Istio configuration"
if kubectl get gateway -n opa-keycloak opa-demo-gateway >/dev/null 2>&1; then
    print_success "✅ Istio Gateway is configured"
    GATEWAY_HOSTS=$(kubectl get gateway -n opa-keycloak opa-demo-gateway -o jsonpath='{.spec.servers[0].hosts[0]}')
    echo "   Gateway host: $GATEWAY_HOSTS"
else
    print_error "❌ Istio Gateway not found"
fi

if kubectl get virtualservice -n opa-keycloak opa-demo-vs >/dev/null 2>&1; then
    print_success "✅ Istio VirtualService is configured"
    VS_ROUTES=$(kubectl get virtualservice -n opa-keycloak opa-demo-vs -o jsonpath='{.spec.http[*].match[0].uri.prefix}' | tr ' ' ',')
    echo "   Configured routes: $VS_ROUTES"
else
    print_error "❌ Istio VirtualService not found"
fi

echo ""
echo "🎯 Connectivity Test Complete"
echo "==============================" 