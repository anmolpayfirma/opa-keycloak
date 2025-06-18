#!/bin/bash

# Authentication Test
# Tests Keycloak token generation and validation

set -e

echo "🔐 Authentication Test"
echo "======================"

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
KEYCLOAK_URL="http://localhost:8082"
REALM="employee-management"
CLIENT_ID="employee-api"
# Note: CLIENT_SECRET needs to be obtained from Keycloak admin console

# Check if Keycloak is accessible
print_status "Checking Keycloak connectivity..."
if ! curl -s --connect-timeout 5 "$KEYCLOAK_URL/health" > /dev/null; then
    print_error "❌ Keycloak is not accessible"
    echo "   Make sure port forwarding is active: kubectl port-forward service/keycloak-service 8082:8080 -n opa-keycloak"
    exit 1
fi

print_success "✅ Keycloak is accessible"
echo ""

# Check realm configuration
print_status "1️⃣  Testing realm configuration..."
REALM_CONFIG=$(curl -s "$KEYCLOAK_URL/realms/$REALM/.well-known/openid_configuration")

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

# Test user credentials (these need to be set up in Keycloak)
print_status "2️⃣  Testing user authentication..."

# Check if CLIENT_SECRET is provided
if [ -z "$CLIENT_SECRET" ]; then
    print_warning "⚠️  CLIENT_SECRET not set"
    echo "   To test authentication, set CLIENT_SECRET environment variable:"
    echo "   export CLIENT_SECRET='your-client-secret-from-keycloak'"
    echo ""
    print_status "Attempting to get client secret from Keycloak admin..."
    echo "   This requires admin access to Keycloak"
    exit 0
fi

# Test users (these should be created by setup-keycloak.sh)
declare -A TEST_USERS=(
    ["alice.manager"]="password123"
    ["bob.employee"]="password123"
    ["jane.hr"]="password123"
)

for username in "${!TEST_USERS[@]}"; do
    password="${TEST_USERS[$username]}"
    
    print_status "Testing user: $username"
    
    TOKEN_RESPONSE=$(curl -s -X POST \
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
        JWT_PAYLOAD_PADDED=$(printf "%s" "$JWT_PAYLOAD" | sed 's/$/===/' | fold -w 4 | head -n -1 | tr -d '\n')
        
        # Decode payload (requires base64 and jq)
        if command -v base64 >/dev/null 2>&1; then
            DECODED_PAYLOAD=$(echo "$JWT_PAYLOAD_PADDED" | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "Could not decode JWT payload")
            if [ "$DECODED_PAYLOAD" != "Could not decode JWT payload" ]; then
                echo "   User: $(echo "$DECODED_PAYLOAD" | jq -r '.preferred_username // "N/A"')"
                echo "   Roles: $(echo "$DECODED_PAYLOAD" | jq -r '.realm_access.roles[]?' | tr '\n' ' ' || echo "N/A")"
                echo "   Employee ID: $(echo "$DECODED_PAYLOAD" | jq -r '.employee_id // "N/A"')"
                echo "   Department: $(echo "$DECODED_PAYLOAD" | jq -r '.department // "N/A"')"
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
        fi
    fi
    
    echo ""
done

# Test token validation with Auth Service (if available)
print_status "3️⃣  Testing token validation..."

AUTH_SERVICE_URL="http://localhost:8081"
if curl -s --connect-timeout 5 "$AUTH_SERVICE_URL/health" > /dev/null; then
    print_status "Auth Service is available, testing token validation..."
    
    if [ -n "$EMPLOYEE_TOKEN" ]; then
        VALIDATION_RESPONSE=$(curl -s -X POST \
            "$AUTH_SERVICE_URL/validate" \
            -H "Content-Type: application/json" \
            -d "{\"token\": \"$EMPLOYEE_TOKEN\"}")
        
        if echo "$VALIDATION_RESPONSE" | jq -e '.valid' > /dev/null 2>&1; then
            IS_VALID=$(echo "$VALIDATION_RESPONSE" | jq -r '.valid')
            if [ "$IS_VALID" = "true" ]; then
                print_success "✅ Token validation successful"
                echo "   User: $(echo "$VALIDATION_RESPONSE" | jq -r '.user.preferred_username // "N/A"')"
            else
                print_error "❌ Token validation failed"
                echo "   Response: $VALIDATION_RESPONSE"
            fi
        else
            print_warning "⚠️  Unexpected validation response"
            echo "   Response: $VALIDATION_RESPONSE"
        fi
    else
        print_warning "⚠️  No employee token available for validation test"
    fi
else
    print_warning "⚠️  Auth Service not accessible"
    echo "   To enable: kubectl port-forward service/auth-service 8081:80 -n opa-keycloak"
fi

echo ""

# Test token refresh
print_status "4️⃣  Testing token refresh..."

if [ -n "$TOKEN_RESPONSE" ] && echo "$TOKEN_RESPONSE" | jq -e '.refresh_token' > /dev/null 2>&1; then
    REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')
    
    REFRESH_RESPONSE=$(curl -s -X POST \
        "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=refresh_token" \
        -d "client_id=$CLIENT_ID" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "refresh_token=$REFRESH_TOKEN")
    
    if echo "$REFRESH_RESPONSE" | jq -e '.access_token' > /dev/null 2>&1; then
        print_success "✅ Token refresh successful"
        echo "   New token expires in: $(echo "$REFRESH_RESPONSE" | jq -r '.expires_in') seconds"
    else
        print_error "❌ Token refresh failed"
        echo "   Response: $REFRESH_RESPONSE"
    fi
else
    print_warning "⚠️  No refresh token available for testing"
fi

echo ""
echo "🎯 Authentication Test Complete"
echo "==============================="

# Export tokens for use in other tests
if [ -n "$EMPLOYEE_TOKEN" ]; then
    echo "export EMPLOYEE_TOKEN='$EMPLOYEE_TOKEN'" > /tmp/test-tokens.env
fi
if [ -n "$MANAGER_TOKEN" ]; then
    echo "export MANAGER_TOKEN='$MANAGER_TOKEN'" >> /tmp/test-tokens.env
fi

if [ -f /tmp/test-tokens.env ]; then
    print_status "Tokens saved to /tmp/test-tokens.env for use in other tests"
    echo "   Source with: source /tmp/test-tokens.env"
fi 