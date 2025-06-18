#!/bin/bash

# Basic Connectivity Test
# Tests if all services are accessible via port forwarding

set -e

echo "🔗 Basic Connectivity Test"
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

# Test configuration
EMPLOYEE_API_URL="http://localhost:3000"
KEYCLOAK_URL="http://localhost:8082"
AUTH_SERVICE_URL="http://localhost:8081"

echo ""
print_status "Testing service connectivity..."

# Test Employee API
print_status "1. Testing Employee API at $EMPLOYEE_API_URL"
if curl -s --connect-timeout 5 "$EMPLOYEE_API_URL/health" > /dev/null; then
    HEALTH_RESPONSE=$(curl -s "$EMPLOYEE_API_URL/health")
    if echo "$HEALTH_RESPONSE" | grep -q '"status": "healthy"'; then
        print_success "✅ Employee API is healthy"
        echo "   Status: $(echo "$HEALTH_RESPONSE" | jq -r '.status')"
        echo "   Database: $(echo "$HEALTH_RESPONSE" | jq -r '.database')"
    else
        print_warning "⚠️  Employee API responded but may have issues"
        echo "   Response: $HEALTH_RESPONSE"
    fi
else
    print_error "❌ Employee API is not accessible"
    echo "   Make sure port forwarding is active: kubectl port-forward service/employee-api-service 3000:8080 -n opa-keycloak"
fi

echo ""

# Test Keycloak
print_status "2. Testing Keycloak at $KEYCLOAK_URL"
if curl -s --connect-timeout 5 "$KEYCLOAK_URL/health" > /dev/null; then
    KEYCLOAK_HEALTH=$(curl -s "$KEYCLOAK_URL/health")
    if echo "$KEYCLOAK_HEALTH" | grep -q '"status": "UP"'; then
        print_success "✅ Keycloak is healthy"
        echo "   Status: $(echo "$KEYCLOAK_HEALTH" | jq -r '.status')"
    else
        print_warning "⚠️  Keycloak responded but may have issues"
        echo "   Response: $KEYCLOAK_HEALTH"
    fi
else
    print_error "❌ Keycloak is not accessible"
    echo "   Make sure port forwarding is active: kubectl port-forward service/keycloak-service 8082:8080 -n opa-keycloak"
fi

echo ""

# Test Auth Service (if available)
print_status "3. Testing Auth Service at $AUTH_SERVICE_URL"
if curl -s --connect-timeout 5 "$AUTH_SERVICE_URL/health" > /dev/null; then
    print_success "✅ Auth Service is accessible"
else
    print_warning "⚠️  Auth Service is not accessible (may not be port-forwarded)"
    echo "   To enable: kubectl port-forward service/auth-service 8081:80 -n opa-keycloak"
fi

echo ""

# Test Employee API data
print_status "4. Testing Employee API data access"
if curl -s --connect-timeout 5 "$EMPLOYEE_API_URL/api/v1/employees" > /dev/null; then
    EMPLOYEES_RESPONSE=$(curl -s "$EMPLOYEE_API_URL/api/v1/employees")
    EMPLOYEE_COUNT=$(echo "$EMPLOYEES_RESPONSE" | jq -r '.count')
    if [ "$EMPLOYEE_COUNT" -gt 0 ]; then
        print_success "✅ Employee data is available"
        echo "   Found $EMPLOYEE_COUNT employees"
        echo "   Sample employee: $(echo "$EMPLOYEES_RESPONSE" | jq -r '.employees[0].name')"
    else
        print_warning "⚠️  No employee data found"
        echo "   Response: $EMPLOYEES_RESPONSE"
    fi
else
    print_error "❌ Cannot access employee data"
fi

echo ""

# Test Keycloak realm
print_status "5. Testing Keycloak realm configuration"
if curl -s --connect-timeout 5 "$KEYCLOAK_URL/realms/employee-management/.well-known/openid_configuration" > /dev/null; then
    REALM_CONFIG=$(curl -s "$KEYCLOAK_URL/realms/employee-management/.well-known/openid_configuration")
    if echo "$REALM_CONFIG" | jq -e '.issuer' > /dev/null 2>&1; then
        print_success "✅ Employee-management realm is configured"
        echo "   Issuer: $(echo "$REALM_CONFIG" | jq -r '.issuer')"
    else
        print_warning "⚠️  Realm exists but configuration may be incomplete"
    fi
else
    print_error "❌ Employee-management realm not found"
    echo "   Run setup-keycloak.sh to configure Keycloak"
fi

echo ""
echo "🎯 Connectivity Test Complete"
echo "==============================" 