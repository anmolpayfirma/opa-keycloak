#!/bin/bash

# Setup Keycloak with employee-management realm, users, and client
# This script configures Keycloak through Istio Gateway

set -e

KEYCLOAK_URL="http://opa-demo.local/auth"
ADMIN_USER="admin"
ADMIN_PASS="admin123"

echo "🔧 Setting up Keycloak..."

# Get admin token
echo "📝 Getting admin token..."
ADMIN_TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$ADMIN_USER&password=$ADMIN_PASS&grant_type=password&client_id=admin-cli" \
  | jq -r '.access_token')

if [ "$ADMIN_TOKEN" = "null" ] || [ -z "$ADMIN_TOKEN" ]; then
  echo "❌ Failed to get admin token"
  exit 1
fi

echo "✅ Got admin token"

# Create employee-management realm
echo "🏢 Creating employee-management realm..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "realm": "employee-management",
    "enabled": true,
    "displayName": "Employee Management"
  }' || echo "Realm might already exist"

# Create employee-api client
echo "🔑 Creating employee-api client..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms/employee-management/clients" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "employee-api",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "secret": "Uh7oAkQ3Tcq68nbynDsNrLEbWsP2Xu8W",
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": true,
    "standardFlowEnabled": true,
    "redirectUris": ["/*"]
  }' || echo "Client might already exist"

# Create employee role
echo "👤 Creating employee role..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms/employee-management/roles" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "employee",
    "description": "Employee role"
  }' || echo "Role might already exist"

# Create manager role
echo "👔 Creating manager role..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms/employee-management/roles" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "manager",
    "description": "Manager role"
  }' || echo "Role might already exist"

# Create bob.employee user
echo "👨‍💼 Creating bob.employee user..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms/employee-management/users" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
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
  }' || echo "User might already exist"

# Get bob.employee user ID
BOB_USER_ID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/employee-management/users?username=bob.employee" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')

# Assign employee role to bob.employee
echo "🎭 Assigning employee role to bob.employee..."
EMPLOYEE_ROLE_ID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/employee-management/roles/employee" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.id')

curl -s -X POST "$KEYCLOAK_URL/admin/realms/employee-management/users/$BOB_USER_ID/role-mappings/realm" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "[{\"id\": \"$EMPLOYEE_ROLE_ID\", \"name\": \"employee\"}]"

# Create alice.manager user
echo "👩‍💼 Creating alice.manager user..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms/employee-management/users" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
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
  }' || echo "User might already exist"

# Get alice.manager user ID
ALICE_USER_ID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/employee-management/users?username=alice.manager" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')

# Assign manager role to alice.manager
echo "🎭 Assigning manager role to alice.manager..."
MANAGER_ROLE_ID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/employee-management/roles/manager" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.id')

curl -s -X POST "$KEYCLOAK_URL/admin/realms/employee-management/users/$ALICE_USER_ID/role-mappings/realm" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "[{\"id\": \"$MANAGER_ROLE_ID\", \"name\": \"manager\"}]"

# Set up protocol mappers for custom attributes
echo "🗂️ Setting up protocol mappers..."

# Get client ID for employee-api
CLIENT_UUID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/employee-management/clients?clientId=employee-api" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')

# Create employee_id mapper
curl -s -X POST "$KEYCLOAK_URL/admin/realms/employee-management/clients/$CLIENT_UUID/protocol-mappers/models" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
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
  }' || echo "Mapper might already exist"

# Create department mapper
curl -s -X POST "$KEYCLOAK_URL/admin/realms/employee-management/clients/$CLIENT_UUID/protocol-mappers/models" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
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
  }' || echo "Mapper might already exist"

echo "✅ Keycloak setup complete!"
echo ""
echo "You can now test authentication:"
echo "curl -X POST $KEYCLOAK_URL/realms/employee-management/protocol/openid-connect/token \\"
echo "  -d 'grant_type=password&client_id=employee-api&client_secret=Uh7oAkQ3Tcq68nbynDsNrLEbWsP2Xu8W&username=bob.employee&password=password123'" 