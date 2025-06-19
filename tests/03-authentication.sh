#!/bin/bash

# Authentication Test
# Tests Keycloak token generation and validation via Istio Gateway

set -e

echo "🔐 Authentication Test (via Istio Gateway)"
echo "=========================================="

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

# Check if Keycloak is accessible
print_status "Checking Keycloak connectivity through Istio Gateway..."
if ! curl -s --connect-timeout 5 -H "Host: $GATEWAY_HOST" "$KEYCLOAK_URL/health" > /dev/null; then
    print_error "❌ Keycloak is not accessible through Istio Gateway"
    echo "   Make sure SSH tunnel is active: ./scripts/setup-tunnel.sh"
    echo "   And /etc/hosts contains: 127.0.0.1 opa-demo.local"
    exit 1
fi

print_success "✅ Keycloak is accessible through Istio Gateway"
echo ""

# Check realm configuration
print_status "1️⃣  Testing realm configuration..."
REALM_CONFIG=$(curl -s -H "Host: $GATEWAY_HOST" "$KEYCLOAK_URL/realms/$REALM/.well-known/openid_configuration")

if echo "$REALM_CONFIG" | jq -e '.issuer' > /dev/null 2>&1; then
    print_success "✅ Realm '$REALM' is configured"
    echo "   Issuer: $(echo "$REALM_CONFIG" | jq -r '.issuer')"
    echo "   Token endpoint: $(echo "$REALM_CONFIG" | jq -r '.token_endpoint')"
    echo "   Auth endpoint: $(echo "$REALM_CONFIG" | jq -r '.authorization_endpoint')"
else
    print_error "❌ Realm '$REALM' not found or misconfigured"
    echo "   Response: $REALM_CONFIG"
    echo "   Run: ./scripts/setup-keycloak.sh to configure Keycloak"
    exit 1
fi

echo ""

# Test user credentials (these are set up by setup-keycloak.sh)
print_status "2️⃣  Testing user authentication..."

# Test users (these should be created by setup-keycloak.sh)
declare -A TEST_USERS=(
    ["alice.manager"]="password123"
    ["bob.employee"]="password123"
)

for username in "${!TEST_USERS[@]}"; do
    password="${TEST_USERS[$username]}"
    
    print_status "Testing user: $username"
    
    TOKEN_RESPONSE=$(curl -s -X POST \
        -H "Host: $GATEWAY_HOST" \
        "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token" \
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
        JWT_HEADER=$(echo "$ACCESS_TOKEN" | cut -d. -f1)
        JWT_PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d. -f2)
        
        # Add padding if needed for base64 decoding
        case $((${#JWT_PAYLOAD} % 4)) in
            2) JWT_PAYLOAD="${JWT_PAYLOAD}==" ;;
            3) JWT_PAYLOAD="${JWT_PAYLOAD}=" ;;
        esac
        
        # Decode payload (requires base64 and jq)
        if command -v base64 >/dev/null 2>&1; then
            DECODED_PAYLOAD=$(echo "$JWT_PAYLOAD" | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "Could not decode JWT payload")
            if [ "$DECODED_PAYLOAD" != "Could not decode JWT payload" ]; then
                echo "   User: $(echo "$DECODED_PAYLOAD" | jq -r '.preferred_username // "N/A"')"
                echo "   Roles: $(echo "$DECODED_PAYLOAD" | jq -r '.realm_access.roles[]?' | tr '\n' ' ' || echo "N/A")"
                echo "   Employee ID: $(echo "$DECODED_PAYLOAD" | jq -r '.employee_id // "N/A"')"
                echo "   Department: $(echo "$DECODED_PAYLOAD" | jq -r '.department // "N/A"')"
                echo "   Email: $(echo "$DECODED_PAYLOAD" | jq -r '.email // "N/A"')"
                echo "   Name: $(echo "$DECODED_PAYLOAD" | jq -r '.name // "N/A"')"
            fi
        fi
        
        # Store token for further testing
        if [ "$username" = "bob.employee" ]; then
            EMPLOYEE_TOKEN="$ACCESS_TOKEN"
        elif [ "$username" = "alice.manager" ]; then
            MANAGER_TOKEN="$ACCESS_TOKEN"
        fi
        
    else
        print_error "❌ Authentication failed for $username"
        echo "   Response: $TOKEN_RESPONSE"
        
        # Check for common error cases
        if echo "$TOKEN_RESPONSE" | grep -q "invalid_client"; then
            echo "   Possible issue: Invalid client credentials"
        elif echo "$TOKEN_RESPONSE" | grep -q "invalid_grant"; then
            echo "   Possible issue: Invalid username/password"
        elif echo "$TOKEN_RESPONSE" | grep -q "unauthorized"; then
            echo "   Possible issue: User not found or realm misconfigured"
        fi
    fi
    
    echo ""
done

# Test Employee API with authentication
print_status "3️⃣  Testing authenticated API access..."

EMPLOYEE_API_URL="$BASE_URL/api/v1/employees"

if [ -n "$EMPLOYEE_TOKEN" ]; then
    print_status "Testing Employee API with bob.employee token..."
    
    # Test GET request with authentication
    AUTH_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -H "Host: $GATEWAY_HOST" \
        -H "Authorization: Bearer $EMPLOYEE_TOKEN" \
        "$EMPLOYEE_API_URL")
    
    AUTH_BODY=$(echo "$AUTH_RESPONSE" | head -n -1)
    AUTH_STATUS=$(echo "$AUTH_RESPONSE" | tail -n 1)
    
    if [ "$AUTH_STATUS" = "200" ]; then
        print_success "✅ Authenticated API access successful"
        if echo "$AUTH_BODY" | jq -e '.count' >/dev/null 2>&1; then
            EMPLOYEE_COUNT=$(echo "$AUTH_BODY" | jq -r '.count')
            echo "   Found $EMPLOYEE_COUNT employees"
        fi
        echo "   Response: $AUTH_BODY"
    elif [ "$AUTH_STATUS" = "501" ] || [ "$AUTH_STATUS" = "401" ] || [ "$AUTH_STATUS" = "403" ]; then
        print_warning "⚠️  API still requires additional authorization (HTTP $AUTH_STATUS)"
        echo "   Token may be valid but OPA policies may be restricting access"
        echo "   Response: $AUTH_BODY"
    else
        print_error "❌ Unexpected API response (HTTP $AUTH_STATUS)"
        echo "   Response: $AUTH_BODY"
    fi
else
    print_warning "⚠️  No employee token available for API testing"
fi

if [ -n "$MANAGER_TOKEN" ]; then
    print_status "Testing Employee API with alice.manager token..."
    
    # Test GET request with manager authentication
    MANAGER_AUTH_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -H "Host: $GATEWAY_HOST" \
        -H "Authorization: Bearer $MANAGER_TOKEN" \
        "$EMPLOYEE_API_URL")
    
    MANAGER_AUTH_BODY=$(echo "$MANAGER_AUTH_RESPONSE" | head -n -1)
    MANAGER_AUTH_STATUS=$(echo "$MANAGER_AUTH_RESPONSE" | tail -n 1)
    
    if [ "$MANAGER_AUTH_STATUS" = "200" ]; then
        print_success "✅ Manager authenticated API access successful"
        if echo "$MANAGER_AUTH_BODY" | jq -e '.count' >/dev/null 2>&1; then
            MANAGER_EMPLOYEE_COUNT=$(echo "$MANAGER_AUTH_BODY" | jq -r '.count')
            echo "   Found $MANAGER_EMPLOYEE_COUNT employees"
        fi
        echo "   Response: $MANAGER_AUTH_BODY"
    elif [ "$MANAGER_AUTH_STATUS" = "501" ] || [ "$MANAGER_AUTH_STATUS" = "401" ] || [ "$MANAGER_AUTH_STATUS" = "403" ]; then
        print_warning "⚠️  Manager API still requires additional authorization (HTTP $MANAGER_AUTH_STATUS)"
        echo "   Token may be valid but OPA policies may be restricting access"
        echo "   Response: $MANAGER_AUTH_BODY"
    else
        print_error "❌ Unexpected manager API response (HTTP $MANAGER_AUTH_STATUS)"
        echo "   Response: $MANAGER_AUTH_BODY"
    fi
else
    print_warning "⚠️  No manager token available for API testing"
fi

echo ""

# Test token refresh
print_status "4️⃣  Testing token refresh..."

if [ -n "$TOKEN_RESPONSE" ] && echo "$TOKEN_RESPONSE" | jq -e '.refresh_token' > /dev/null 2>&1; then
    REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')
    
    REFRESH_RESPONSE=$(curl -s -X POST \
        -H "Host: $GATEWAY_HOST" \
        "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=refresh_token" \
        -d "client_id=$CLIENT_ID" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "refresh_token=$REFRESH_TOKEN")
    
    if echo "$REFRESH_RESPONSE" | jq -e '.access_token' > /dev/null 2>&1; then
        print_success "✅ Token refresh successful"
        NEW_ACCESS_TOKEN=$(echo "$REFRESH_RESPONSE" | jq -r '.access_token')
        echo "   New token obtained (length: ${#NEW_ACCESS_TOKEN} chars)"
    else
        print_error "❌ Token refresh failed"
        echo "   Response: $REFRESH_RESPONSE"
    fi
else
    print_warning "⚠️  No refresh token available for testing"
fi

echo ""

# Test OPA integration (if available)
print_status "5️⃣  Testing OPA integration..."

OPA_URL="$BASE_URL/opa/v1/data"
if curl -s --connect-timeout 5 -H "Host: $GATEWAY_HOST" "$OPA_URL" >/dev/null 2>&1; then
    print_status "OPA is accessible, testing policy evaluation..."
    
    if [ -n "$EMPLOYEE_TOKEN" ]; then
        # Test OPA policy decision
        OPA_QUERY='{
            "input": {
                "method": "GET",
                "path": "/api/v1/employees",
                "user": {
                    "roles": ["employee"],
                    "employee_id": "EMP003",
                    "department": "Engineering"
                }
            }
        }'
        
        OPA_RESPONSE=$(curl -s -X POST \
            -H "Host: $GATEWAY_HOST" \
            -H "Content-Type: application/json" \
            -d "$OPA_QUERY" \
            "$OPA_URL/authz/allow")
        
        if echo "$OPA_RESPONSE" | jq -e '.result' >/dev/null 2>&1; then
            ALLOW_RESULT=$(echo "$OPA_RESPONSE" | jq -r '.result')
            if [ "$ALLOW_RESULT" = "true" ]; then
                print_success "✅ OPA policy allows employee access"
            else
                print_warning "⚠️  OPA policy denies employee access"
            fi
            echo "   Policy result: $ALLOW_RESULT"
        else
            print_warning "⚠️  OPA response format unexpected"
            echo "   Response: $OPA_RESPONSE"
        fi
    else
        print_warning "⚠️  No token available for OPA policy testing"
    fi
else
    print_warning "⚠️  OPA not accessible through Istio Gateway"
    echo "   Check OPA routing configuration"
fi

echo ""

# Summary
print_status "📊 Authentication Test Summary"
echo "==============================="
if [ -n "$EMPLOYEE_TOKEN" ] && [ -n "$MANAGER_TOKEN" ]; then
    print_success "✅ Both employee and manager authentication successful"
    echo ""
    print_status "💡 You can use these tokens for manual API testing:"
    echo ""
    echo "Employee Token (bob.employee):"
    echo "curl -H 'Authorization: Bearer $EMPLOYEE_TOKEN' $EMPLOYEE_API_URL"
    echo ""
    echo "Manager Token (alice.manager):"
    echo "curl -H 'Authorization: Bearer $MANAGER_TOKEN' $EMPLOYEE_API_URL"
elif [ -n "$EMPLOYEE_TOKEN" ] || [ -n "$MANAGER_TOKEN" ]; then
    print_warning "⚠️  Partial authentication success"
    echo "   Some users authenticated successfully"
else
    print_error "❌ No users authenticated successfully"
    echo "   Check Keycloak configuration and user setup"
fi

echo ""
echo "🎯 Authentication Test Complete"
echo "===============================" 