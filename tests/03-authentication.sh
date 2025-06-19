#!/bin/bash

# Authentication & Authorization Test
# Tests Keycloak token generation and OPA-Istio authorization

set -e

echo "🔐 Authentication & Authorization Test (Istio + OPA)"
echo "===================================================="

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
KEYCLOAK_URL="$BASE_URL/auth"
REALM="employee-management"
CLIENT_ID="employee-api"
CLIENT_SECRET="Uh7oAkQ3Tcq68nbynDsNrLEbWsP2Xu8W"

# API endpoints
EMPLOYEE_API_URL="$BASE_URL/api/v1/employees"
HEALTH_URL="$BASE_URL/health"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to track test results
track_test() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ "$1" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Function to test HTTP endpoint
test_endpoint() {
    local description="$1"
    local expected_status="$2"
    local curl_args="$3"
    
    print_status "Testing: $description"
    
    RESPONSE=$(eval "curl -s -w '\n%{http_code}' $curl_args" 2>/dev/null || echo -e "\nERROR")
    BODY=$(echo "$RESPONSE" | head -n -1)
    STATUS=$(echo "$RESPONSE" | tail -n 1)
    
    if [ "$STATUS" = "$expected_status" ]; then
        print_success "✅ PASS: $description (HTTP $STATUS)"
        track_test "PASS"
        return 0
    else
        print_error "❌ FAIL: $description (Expected: $expected_status, Got: $STATUS)"
        if [ "$STATUS" != "ERROR" ] && [ -n "$BODY" ]; then
            echo "   Response: $BODY"
        fi
        track_test "FAIL"
        return 1
    fi
}

# Check prerequisites
print_status "Checking prerequisites..."

# Check if SSH tunnel is active
if ! curl -s --connect-timeout 5 -H "Host: $GATEWAY_HOST" "$HEALTH_URL" > /dev/null; then
    print_error "❌ Cannot access services through Istio Gateway"
    echo "   Make sure SSH tunnel is active: ./scripts/setup-tunnel.sh"
    echo "   And /etc/hosts contains: 127.0.0.1 opa-demo.local"
    exit 1
fi

print_success "✅ Services accessible through Istio Gateway"
echo ""

# Check realm configuration
print_status "1️⃣  Testing Keycloak realm configuration..."

# Use direct token endpoint since realm discovery might not be exposed through Istio
TOKEN_ENDPOINT="$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token"

# Test if we can reach the token endpoint by attempting authentication
print_status "Testing token endpoint accessibility..."
TEST_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null -X POST \
    -H "Host: $GATEWAY_HOST" \
    "$TOKEN_ENDPOINT" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "username=test" \
    -d "password=test")

if [ "$TEST_RESPONSE" = "401" ] || [ "$TEST_RESPONSE" = "400" ]; then
    print_success "✅ Keycloak token endpoint is accessible"
    echo "   Token endpoint: $TOKEN_ENDPOINT"
else
    print_error "❌ Keycloak token endpoint not accessible (HTTP $TEST_RESPONSE)"
    echo "   Check if Keycloak is properly configured and accessible"
    echo "   Run: ./scripts/setup-keycloak.sh to configure Keycloak"
    exit 1
fi

echo ""

# Test user authentication
print_status "2️⃣  Testing user authentication..."

# Test users - using simple arrays to avoid bash associative array issues
TEST_USERNAMES=("alice.manager" "bob.employee")
TEST_PASSWORDS=("password123" "password123")

EMPLOYEE_TOKEN=""
MANAGER_TOKEN=""

for i in "${!TEST_USERNAMES[@]}"; do
    username="${TEST_USERNAMES[$i]}"
    password="${TEST_PASSWORDS[$i]}"
    
    print_status "Authenticating user: $username"
    
    TOKEN_RESPONSE=$(curl -s -X POST \
        -H "Host: $GATEWAY_HOST" \
        "$TOKEN_ENDPOINT" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password" \
        -d "client_id=$CLIENT_ID" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "username=$username" \
        -d "password=$password")
    
    if echo "$TOKEN_RESPONSE" | jq -e '.access_token' > /dev/null 2>&1; then
        ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
        print_success "✅ Authentication successful for $username"
        
        # Decode JWT token to show claims
        JWT_PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d. -f2)
        
        # Add padding if needed for base64 decoding
        case $((${#JWT_PAYLOAD} % 4)) in
            2) JWT_PAYLOAD="${JWT_PAYLOAD}==" ;;
            3) JWT_PAYLOAD="${JWT_PAYLOAD}=" ;;
        esac
        
        # Decode payload
        if command -v base64 >/dev/null 2>&1; then
            DECODED_PAYLOAD=$(echo "$JWT_PAYLOAD" | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "Could not decode JWT payload")
            if [ "$DECODED_PAYLOAD" != "Could not decode JWT payload" ]; then
                echo "   User: $(echo "$DECODED_PAYLOAD" | jq -r '.preferred_username // "N/A"')"
                echo "   Roles: $(echo "$DECODED_PAYLOAD" | jq -r '.realm_access.roles[]?' | tr '\n' ' ' || echo "N/A")"
                echo "   Employee ID: $(echo "$DECODED_PAYLOAD" | jq -r '.employee_id // "N/A"')"
                echo "   Department: $(echo "$DECODED_PAYLOAD" | jq -r '.department // "N/A"')"
            fi
        fi
        
        # Store tokens for authorization testing
        if [ "$username" = "bob.employee" ]; then
            EMPLOYEE_TOKEN="$ACCESS_TOKEN"
        elif [ "$username" = "alice.manager" ]; then
            MANAGER_TOKEN="$ACCESS_TOKEN"
        fi
        
    else
        print_error "❌ Authentication failed for $username"
        echo "   Response: $TOKEN_RESPONSE"
    fi
    
    echo ""
done

# Test unauthorized access
print_status "3️⃣  Testing unauthorized access (no token)..."
echo ""

test_endpoint "Health check without auth" "200" "-H 'Host: $GATEWAY_HOST' '$HEALTH_URL'"
test_endpoint "Employee API without auth" "403" "-H 'Host: $GATEWAY_HOST' '$EMPLOYEE_API_URL'"
test_endpoint "Employee API POST without auth" "403" "-X POST -H 'Host: $GATEWAY_HOST' -H 'Content-Type: application/json' -d '{\"id\":\"TEST\"}' '$EMPLOYEE_API_URL'"

echo ""

# Test employee authorization
if [ -n "$EMPLOYEE_TOKEN" ]; then
    print_status "4️⃣  Testing employee authorization (bob.employee)..."
    echo ""
    
    test_endpoint "Employee GET request" "200" "-H 'Host: $GATEWAY_HOST' -H 'Authorization: Bearer $EMPLOYEE_TOKEN' '$EMPLOYEE_API_URL'"
    test_endpoint "Employee POST request (should be denied)" "403" "-X POST -H 'Host: $GATEWAY_HOST' -H 'Authorization: Bearer $EMPLOYEE_TOKEN' -H 'Content-Type: application/json' -d '{\"id\":\"TEST\",\"name\":\"Test\"}' '$EMPLOYEE_API_URL'"
    test_endpoint "Employee PUT request (should be denied)" "403" "-X PUT -H 'Host: $GATEWAY_HOST' -H 'Authorization: Bearer $EMPLOYEE_TOKEN' -H 'Content-Type: application/json' -d '{\"name\":\"Updated\"}' '$EMPLOYEE_API_URL/EMP001'"
    test_endpoint "Employee DELETE request (should be denied)" "403" "-X DELETE -H 'Host: $GATEWAY_HOST' -H 'Authorization: Bearer $EMPLOYEE_TOKEN' '$EMPLOYEE_API_URL/EMP001'"
    
    echo ""
else
    print_warning "⚠️  No employee token available for authorization testing"
fi

# Test manager authorization
if [ -n "$MANAGER_TOKEN" ]; then
    print_status "5️⃣  Testing manager authorization (alice.manager)..."
    echo ""
    
    test_endpoint "Manager GET request" "200" "-H 'Host: $GATEWAY_HOST' -H 'Authorization: Bearer $MANAGER_TOKEN' '$EMPLOYEE_API_URL'"
    
    # For POST, we expect either 201 (success) or 400 (validation error) - both indicate auth passed
    print_status "Testing: Manager POST request"
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST -H "Host: $GATEWAY_HOST" -H "Authorization: Bearer $MANAGER_TOKEN" -H "Content-Type: application/json" -d '{"id":"TESTMGR","name":"Test Manager","department":"IT"}' "$EMPLOYEE_API_URL" 2>/dev/null || echo -e "\nERROR")
    STATUS=$(echo "$RESPONSE" | tail -n 1)
    
    if [ "$STATUS" = "201" ] || [ "$STATUS" = "400" ]; then
        print_success "✅ PASS: Manager POST request (HTTP $STATUS - Authorization successful)"
        track_test "PASS"
    else
        print_error "❌ FAIL: Manager POST request (Expected: 201 or 400, Got: $STATUS)"
        track_test "FAIL"
    fi
    
    # Similar for PUT and DELETE
    print_status "Testing: Manager PUT request"
    RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT -H "Host: $GATEWAY_HOST" -H "Authorization: Bearer $MANAGER_TOKEN" -H "Content-Type: application/json" -d '{"name":"Updated Manager"}' "$EMPLOYEE_API_URL/EMP001" 2>/dev/null || echo -e "\nERROR")
    STATUS=$(echo "$RESPONSE" | tail -n 1)
    
    if [ "$STATUS" = "200" ] || [ "$STATUS" = "400" ] || [ "$STATUS" = "404" ]; then
        print_success "✅ PASS: Manager PUT request (HTTP $STATUS - Authorization successful)"
        track_test "PASS"
    else
        print_error "❌ FAIL: Manager PUT request (Expected: 200/400/404, Got: $STATUS)"
        track_test "FAIL"
    fi
    
    print_status "Testing: Manager DELETE request"
    RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE -H "Host: $GATEWAY_HOST" -H "Authorization: Bearer $MANAGER_TOKEN" "$EMPLOYEE_API_URL/EMP999" 2>/dev/null || echo -e "\nERROR")
    STATUS=$(echo "$RESPONSE" | tail -n 1)
    
    if [ "$STATUS" = "200" ] || [ "$STATUS" = "404" ]; then
        print_success "✅ PASS: Manager DELETE request (HTTP $STATUS - Authorization successful)"
        track_test "PASS"
    else
        print_error "❌ FAIL: Manager DELETE request (Expected: 200/404, Got: $STATUS)"
        track_test "FAIL"
    fi
    
    echo ""
else
    print_warning "⚠️  No manager token available for authorization testing"
fi

# Test token refresh
if [ -n "$TOKEN_RESPONSE" ] && echo "$TOKEN_RESPONSE" | jq -e '.refresh_token' > /dev/null 2>&1; then
    print_status "6️⃣  Testing token refresh..."
    
    REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')
    
    REFRESH_RESPONSE=$(curl -s -X POST \
        -H "Host: $GATEWAY_HOST" \
        "$TOKEN_ENDPOINT" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=refresh_token" \
        -d "client_id=$CLIENT_ID" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "refresh_token=$REFRESH_TOKEN")
    
    if echo "$REFRESH_RESPONSE" | jq -e '.access_token' > /dev/null 2>&1; then
        print_success "✅ Token refresh successful"
        track_test "PASS"
    else
        print_error "❌ Token refresh failed"
        track_test "FAIL"
    fi
    
    echo ""
fi

# Test OPA decision logging (if kubectl is available)
if command -v kubectl >/dev/null 2>&1; then
    print_status "7️⃣  Testing OPA decision logging..."
    
    if kubectl get pods -n opa-keycloak -l app=opa-envoy >/dev/null 2>&1; then
        RECENT_DECISIONS=$(kubectl logs -l app=opa-envoy -n opa-keycloak --tail=10 2>/dev/null | grep -c "decision" || echo "0")
        if [ "$RECENT_DECISIONS" -gt "0" ]; then
            print_success "✅ OPA decision logging active ($RECENT_DECISIONS recent decisions)"
            
            # Show last decision result
            LAST_DECISION=$(kubectl logs -l app=opa-envoy -n opa-keycloak --tail=20 2>/dev/null | grep decision | tail -1 | jq -r '.result' 2>/dev/null || echo "unknown")
            echo "   Last decision result: $LAST_DECISION"
            track_test "PASS"
        else
            print_warning "⚠️  No recent OPA decisions found"
            track_test "FAIL"
        fi
    else
        print_warning "⚠️  OPA-Envoy pods not found"
        track_test "FAIL"
    fi
    
    echo ""
fi

# Performance test
print_status "8️⃣  Testing response performance..."

if [ -n "$EMPLOYEE_TOKEN" ]; then
    print_status "Measuring API response time with authentication..."
    
    START_TIME=$(date +%s%3N)
    curl -s -H "Host: $GATEWAY_HOST" -H "Authorization: Bearer $EMPLOYEE_TOKEN" "$EMPLOYEE_API_URL" >/dev/null 2>&1
    END_TIME=$(date +%s%3N)
    RESPONSE_TIME=$((END_TIME - START_TIME))
    
    print_success "✅ Authenticated API response time: ${RESPONSE_TIME}ms"
    
    if [ "$RESPONSE_TIME" -lt 500 ]; then
        print_success "   Performance: Excellent (< 500ms)"
        track_test "PASS"
    elif [ "$RESPONSE_TIME" -lt 1000 ]; then
        print_success "   Performance: Good (< 1000ms)"
        track_test "PASS"
    else
        print_warning "   Performance: Could be improved (> 1000ms)"
        track_test "FAIL"
    fi
else
    print_warning "⚠️  No token available for performance testing"
fi

echo ""

# Summary
print_status "📊 Test Summary"
echo "==============="
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"

if [ "$FAILED_TESTS" -eq 0 ]; then
    print_success "🎉 All tests passed! Authentication and authorization working perfectly."
    
    if [ -n "$EMPLOYEE_TOKEN" ] && [ -n "$MANAGER_TOKEN" ]; then
        echo ""
        print_status "💡 Manual testing commands:"
        echo ""
        echo "# Employee (read-only access):"
        echo "curl -H 'Host: $GATEWAY_HOST' -H 'Authorization: Bearer $EMPLOYEE_TOKEN' '$EMPLOYEE_API_URL'"
        echo ""
        echo "# Manager (full access):"
        echo "curl -H 'Host: $GATEWAY_HOST' -H 'Authorization: Bearer $MANAGER_TOKEN' '$EMPLOYEE_API_URL'"
        echo "curl -X POST -H 'Host: $GATEWAY_HOST' -H 'Authorization: Bearer $MANAGER_TOKEN' -H 'Content-Type: application/json' -d '{\"id\":\"NEW001\",\"name\":\"New Employee\",\"department\":\"IT\"}' '$EMPLOYEE_API_URL'"
    fi
    
    exit 0
elif [ "$PASSED_TESTS" -gt 0 ]; then
    print_warning "⚠️  Some tests failed. Check the configuration."
    exit 1
else
    print_error "❌ All tests failed. Check Keycloak and OPA configuration."
    exit 1
fi

echo ""
echo "🎯 Authentication & Authorization Test Complete"
echo "===============================================" 