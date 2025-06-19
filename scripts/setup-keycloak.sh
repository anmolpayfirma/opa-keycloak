#!/bin/bash

# Setup Keycloak with employee-management realm, users, and client
# This script configures Keycloak through Istio Gateway

set -e

KEYCLOAK_URL="http://opa-demo.local/auth"
ADMIN_USER="admin"
ADMIN_PASS="admin123"

echo "🔧 Setting up Keycloak..."

# Function to get fresh admin token
get_admin_token() {
  local token=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$ADMIN_USER&password=$ADMIN_PASS&grant_type=password&client_id=admin-cli" \
    | jq -r '.access_token')
  
  if [ "$token" = "null" ] || [ -z "$token" ]; then
    echo "❌ Failed to get admin token"
    exit 1
  fi
  
  echo "$token"
}

# Function to make authenticated API calls with fresh token
api_call() {
  local method="$1"
  local url="$2"
  local data="$3"
  local content_type="${4:-application/json}"
  
  local token=$(get_admin_token)
  
  if [ -n "$data" ]; then
    curl -s -X "$method" "$url" \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: $content_type" \
      -d "$data"
  else
    curl -s -X "$method" "$url" \
      -H "Authorization: Bearer $token"
  fi
}

# Get admin token
echo "📝 Getting admin token..."
ADMIN_TOKEN=$(get_admin_token)
echo "✅ Got admin token"

# Create employee-management realm
echo "🏢 Creating employee-management realm..."
api_call POST "$KEYCLOAK_URL/admin/realms" '{
  "realm": "employee-management",
  "enabled": true,
  "displayName": "Employee Management"
}' > /dev/null || echo "Realm might already exist"

# Create employee-api client
echo "🔑 Creating employee-api client..."
api_call POST "$KEYCLOAK_URL/admin/realms/employee-management/clients" '{
  "clientId": "employee-api",
  "enabled": true,
  "clientAuthenticatorType": "client-secret",
  "secret": "Uh7oAkQ3Tcq68nbynDsNrLEbWsP2Xu8W",
  "directAccessGrantsEnabled": true,
  "serviceAccountsEnabled": true,
  "standardFlowEnabled": true,
  "redirectUris": ["/*"]
}' > /dev/null || echo "Client might already exist"

# Create employee role
echo "👤 Creating employee role..."
api_call POST "$KEYCLOAK_URL/admin/realms/employee-management/roles" '{
  "name": "employee",
  "description": "Employee role"
}' > /dev/null || echo "Role might already exist"

# Create manager role
echo "👔 Creating manager role..."
api_call POST "$KEYCLOAK_URL/admin/realms/employee-management/roles" '{
  "name": "manager",
  "description": "Manager role"
}' > /dev/null || echo "Role might already exist"

# Create bob.employee user
echo "👨‍💼 Creating bob.employee user..."
api_call POST "$KEYCLOAK_URL/admin/realms/employee-management/users" '{
  "username": "bob.employee",
  "enabled": true,
  "firstName": "Bob",
  "lastName": "Employee",
  "email": "bob@company.com",
  "attributes": {
    "employee_id": ["EMP003"],
    "department": ["Engineering"]
  },
  "credentials": [{
    "type": "password",
    "value": "password123",
    "temporary": false
  }]
}' > /dev/null || echo "User might already exist"

# Get bob.employee user ID
BOB_USER_RESPONSE=$(api_call GET "$KEYCLOAK_URL/admin/realms/employee-management/users?username=bob.employee")
BOB_USER_ID=$(echo "$BOB_USER_RESPONSE" | jq -r 'if type == "array" and length > 0 then .[0].id else empty end')

if [ -z "$BOB_USER_ID" ]; then
  echo "❌ Failed to get bob.employee user ID"
  exit 1
fi

# Assign employee role to bob.employee
echo "🎭 Assigning employee role to bob.employee..."
EMPLOYEE_ROLE_RESPONSE=$(api_call GET "$KEYCLOAK_URL/admin/realms/employee-management/roles/employee")
EMPLOYEE_ROLE_ID=$(echo "$EMPLOYEE_ROLE_RESPONSE" | jq -r 'if has("id") then .id else empty end')

if [ -n "$EMPLOYEE_ROLE_ID" ]; then
  api_call POST "$KEYCLOAK_URL/admin/realms/employee-management/users/$BOB_USER_ID/role-mappings/realm" \
    "[{\"id\": \"$EMPLOYEE_ROLE_ID\", \"name\": \"employee\"}]" > /dev/null
fi

# Create alice.manager user
echo "👩‍💼 Creating alice.manager user..."
api_call POST "$KEYCLOAK_URL/admin/realms/employee-management/users" '{
  "username": "alice.manager",
  "enabled": true,
  "firstName": "Alice",
  "lastName": "Manager",
  "email": "alice@company.com",
  "attributes": {
    "employee_id": ["MGR001"],
    "department": ["Management"]
  },
  "credentials": [{
    "type": "password",
    "value": "password123",
    "temporary": false
  }]
}' > /dev/null || echo "User might already exist"

# Get alice.manager user ID
ALICE_USER_RESPONSE=$(api_call GET "$KEYCLOAK_URL/admin/realms/employee-management/users?username=alice.manager")
ALICE_USER_ID=$(echo "$ALICE_USER_RESPONSE" | jq -r 'if type == "array" and length > 0 then .[0].id else empty end')

if [ -z "$ALICE_USER_ID" ]; then
  echo "❌ Failed to get alice.manager user ID"
  exit 1
fi

# Assign manager role to alice.manager
echo "🎭 Assigning manager role to alice.manager..."
MANAGER_ROLE_RESPONSE=$(api_call GET "$KEYCLOAK_URL/admin/realms/employee-management/roles/manager")
MANAGER_ROLE_ID=$(echo "$MANAGER_ROLE_RESPONSE" | jq -r 'if has("id") then .id else empty end')

if [ -n "$MANAGER_ROLE_ID" ]; then
  api_call POST "$KEYCLOAK_URL/admin/realms/employee-management/users/$ALICE_USER_ID/role-mappings/realm" \
    "[{\"id\": \"$MANAGER_ROLE_ID\", \"name\": \"manager\"}]" > /dev/null
fi

# Set up protocol mappers for custom attributes
echo "🗂️ Setting up protocol mappers..."

# Get client ID for employee-api
CLIENT_RESPONSE=$(api_call GET "$KEYCLOAK_URL/admin/realms/employee-management/clients?clientId=employee-api")
CLIENT_UUID=$(echo "$CLIENT_RESPONSE" | jq -r 'if type == "array" and length > 0 then .[0].id else empty end')

if [ -z "$CLIENT_UUID" ]; then
  echo "❌ Failed to get employee-api client UUID"
  exit 1
fi

# Create employee_id mapper
api_call POST "$KEYCLOAK_URL/admin/realms/employee-management/clients/$CLIENT_UUID/protocol-mappers/models" '{
  "name": "employee_id",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-attribute-mapper",
  "config": {
    "user.attribute": "employee_id",
    "claim.name": "employee_id",
    "jsonType.label": "String",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true"
  }
}' > /dev/null || echo "Mapper might already exist"

# Create department mapper
api_call POST "$KEYCLOAK_URL/admin/realms/employee-management/clients/$CLIENT_UUID/protocol-mappers/models" '{
  "name": "department",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-attribute-mapper",
  "config": {
    "user.attribute": "department",
    "claim.name": "department",
    "jsonType.label": "String",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true"
  }
}' > /dev/null || echo "Mapper might already exist"

echo "✅ Keycloak setup complete!"
echo ""
echo "You can now test authentication:"
echo "curl -X POST $KEYCLOAK_URL/realms/employee-management/protocol/openid-connect/token \\"
echo "  -d 'grant_type=password&client_id=employee-api&client_secret=Uh7oAkQ3Tcq68nbynDsNrLEbWsP2Xu8W&username=bob.employee&password=password123'" 