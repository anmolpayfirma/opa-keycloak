#!/bin/bash

# Add New API Script
# Automates the process of integrating a new API into the Istio + OPA + Keycloak setup

set -e

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

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Usage function
usage() {
    echo "Usage: $0 --name <api-name> --resource <resource-name> [OPTIONS]"
    echo ""
    echo "Required:"
    echo "  --name <api-name>        Name of the API (e.g., merchant-api, user-api)"
    echo "  --resource <resource>    Resource name (e.g., merchants, users)"
    echo ""
    echo "Options:"
    echo "  --port <port>           API port (default: 8080)"
    echo "  --template <template>   Template type: crud|admin|public|tenant (default: crud)"
    echo "  --roles <roles>         Comma-separated roles for access (default: employee,manager)"
    echo "  --language <lang>       Language template: python|go|nodejs|java (optional)"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --name merchant-api --resource merchants"
    echo "  $0 --name user-api --resource users --template admin --roles admin"
    echo "  $0 --name catalog-api --resource products --template public --language go"
}

# Default values
API_NAME=""
RESOURCE_NAME=""
API_PORT="8080"
TEMPLATE_TYPE="crud"
ROLES="employee,manager"
LANGUAGE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name)
            API_NAME="$2"
            shift 2
            ;;
        --resource)
            RESOURCE_NAME="$2"
            shift 2
            ;;
        --port)
            API_PORT="$2"
            shift 2
            ;;
        --template)
            TEMPLATE_TYPE="$2"
            shift 2
            ;;
        --roles)
            ROLES="$2"
            shift 2
            ;;
        --language)
            LANGUAGE="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$API_NAME" ] || [ -z "$RESOURCE_NAME" ]; then
    print_error "Missing required parameters"
    usage
    exit 1
fi

# Validate template type
if [[ ! "$TEMPLATE_TYPE" =~ ^(crud|admin|public|tenant)$ ]]; then
    print_error "Invalid template type. Must be one of: crud, admin, public, tenant"
    exit 1
fi

# Convert names to different formats
API_NAME_UNDERSCORE=$(echo "$API_NAME" | tr '-' '_')
API_NAME_CAMEL=$(echo "$API_NAME" | sed -r 's/(^|-)([a-z])/\U\2/g')
RESOURCE_NAME_SINGULAR=$(echo "$RESOURCE_NAME" | sed 's/s$//')

print_status "🚀 Adding new API: $API_NAME"
echo "  Resource: $RESOURCE_NAME"
echo "  Port: $API_PORT"
echo "  Template: $TEMPLATE_TYPE"
echo "  Roles: $ROLES"
if [ -n "$LANGUAGE" ]; then
    echo "  Language: $LANGUAGE"
fi
echo ""

# 1. Create Helm template
print_status "1️⃣ Creating Helm template..."

HELM_TEMPLATE="helm/opa-keycloak/templates/${API_NAME}.yaml"

cat > "$HELM_TEMPLATE" << EOF
{{- if .Values.${API_NAME_UNDERSCORE}.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${API_NAME}
  namespace: {{ .Values.global.namespace }}
  labels:
    app: ${API_NAME}
    version: v1
spec:
  replicas: {{ .Values.${API_NAME_UNDERSCORE}.replicas | default 1 }}
  selector:
    matchLabels:
      app: ${API_NAME}
      version: v1
  template:
    metadata:
      labels:
        app: ${API_NAME}
        version: v1
    spec:
      containers:
      - name: ${API_NAME}
        image: "{{ .Values.${API_NAME_UNDERSCORE}.image.repository }}:{{ .Values.${API_NAME_UNDERSCORE}.image.tag }}"
        ports:
        - containerPort: ${API_PORT}
        resources:
          {{- toYaml .Values.${API_NAME_UNDERSCORE}.resources | nindent 10 }}
        env:
        - name: PORT
          value: "${API_PORT}"
        livenessProbe:
          httpGet:
            path: /health
            port: ${API_PORT}
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: ${API_PORT}
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: ${API_NAME}-service
  namespace: {{ .Values.global.namespace }}
  labels:
    app: ${API_NAME}
spec:
  selector:
    app: ${API_NAME}
  ports:
  - port: ${API_PORT}
    targetPort: ${API_PORT}
    name: http
{{- end }}
EOF

print_success "✅ Created Helm template: $HELM_TEMPLATE"

# 2. Update values.yaml
print_status "2️⃣ Updating values.yaml..."

VALUES_FILE="helm/opa-keycloak/values.yaml"

# Add API configuration to values.yaml
cat >> "$VALUES_FILE" << EOF

# ${API_NAME_CAMEL} API Configuration
${API_NAME_UNDERSCORE}:
  enabled: true
  image:
    repository: ${API_NAME}
    tag: latest
  replicas: 1
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"
EOF

print_success "✅ Updated values.yaml with $API_NAME configuration"

# 3. Update Istio Gateway
print_status "3️⃣ Updating Istio Gateway routing..."

GATEWAY_FILE="helm/opa-keycloak/templates/istio-gateway.yaml"

# Create backup
cp "$GATEWAY_FILE" "${GATEWAY_FILE}.backup"

# Add route before the OPA routes section
ROUTE_CONFIG="  # ${API_NAME_CAMEL} routes
  - match:
    - uri:
        prefix: /api/v1/${RESOURCE_NAME}
    route:
    - destination:
        host: ${API_NAME}-service
        port:
          number: ${API_PORT}
  # Health check for ${API_NAME}
  - match:
    - uri:
        exact: /${RESOURCE_NAME_SINGULAR}-health
    rewrite:
      uri: /health
    route:
    - destination:
        host: ${API_NAME}-service
        port:
          number: ${API_PORT}"

# Insert the route before OPA routes (using different approach for macOS)
# Create temporary file with the route insertion
awk -v route="$ROUTE_CONFIG" '
/# OPA routes/ {
    print route
    print ""
}
{print}
' "$GATEWAY_FILE" > "${GATEWAY_FILE}.tmp" && mv "${GATEWAY_FILE}.tmp" "$GATEWAY_FILE"

# Clean up temp file (if it exists)
[ -f "${GATEWAY_FILE}.tmp" ] && rm "${GATEWAY_FILE}.tmp"

print_success "✅ Updated Istio Gateway with $API_NAME routes"

# 4. Create OPA policy
print_status "4️⃣ Creating OPA authorization policy..."

OPA_POLICY_FILE="docs/opa-policies/${API_NAME}-policy.rego"
mkdir -p "docs/opa-policies"

# Generate policy based on template type
case $TEMPLATE_TYPE in
    "crud")
        POLICY_RULES='
# CRUD API - Read access for employees, write for managers
has_'${RESOURCE_NAME_SINGULAR}'_permission if {
    input.attributes.request.http.method == "GET"
    user_has_role(["employee", "manager", "admin"])
}

has_'${RESOURCE_NAME_SINGULAR}'_permission if {
    input.attributes.request.http.method in ["POST", "PUT", "DELETE"]
    user_has_role(["manager", "admin"])
}'
        ;;
    "admin")
        POLICY_RULES='
# Admin API - Admin access only
has_'${RESOURCE_NAME_SINGULAR}'_permission if {
    user_has_role(["admin"])
}'
        ;;
    "public")
        POLICY_RULES='
# Public API - Read access for all, write for admin
has_'${RESOURCE_NAME_SINGULAR}'_permission if {
    input.attributes.request.http.method == "GET"
    # No auth required for read
}

has_'${RESOURCE_NAME_SINGULAR}'_permission if {
    input.attributes.request.http.method in ["POST", "PUT", "DELETE"]
    user_has_role(["admin"])
}'
        ;;
    "tenant")
        POLICY_RULES='
# Tenant API - Tenant-specific access
has_'${RESOURCE_NAME_SINGULAR}'_permission if {
    input.attributes.request.http.method == "GET"
    user_has_role(["employee", "manager", "tenant-user"])
    # Add tenant isolation logic here
}

has_'${RESOURCE_NAME_SINGULAR}'_permission if {
    input.attributes.request.http.method in ["POST", "PUT", "DELETE"]
    user_has_role(["manager", "tenant-admin"])
    # Add tenant isolation logic here
}'
        ;;
esac

cat > "$OPA_POLICY_FILE" << EOF
package istio.authz

import rego.v1

# ${API_NAME_CAMEL} API Authorization Policy
# Generated automatically by add-new-api.sh

# Main authorization rule for ${API_NAME}
allow if {
    is_${RESOURCE_NAME_SINGULAR}_api_request
    is_authenticated
    has_${RESOURCE_NAME_SINGULAR}_permission
}

# Check if request is for ${API_NAME}
is_${RESOURCE_NAME_SINGULAR}_api_request if {
    startswith(input.attributes.request.http.path, "/api/v1/${RESOURCE_NAME}")
}

${POLICY_RULES}

# Helper function to check user roles (reusable)
user_has_role(required_roles) if {
    some role in required_roles
    role in token_payload.realm_access.roles
}

# Extract token payload (reusable)
token_payload := payload if {
    auth_header := input.attributes.request.http.headers.authorization
    token := substring(auth_header, 7, -1)  # Remove "Bearer "
    parts := io.jwt.decode(token)
    payload := parts[1]
}
EOF

print_success "✅ Created OPA policy: $OPA_POLICY_FILE"

# 5. Create integration test
print_status "5️⃣ Creating integration test..."

TEST_FILE="tests/$(printf "%02d" $(($(ls tests/*.sh 2>/dev/null | wc -l) + 1)))-${API_NAME}.sh"

cat > "$TEST_FILE" << EOF
#!/bin/bash

# ${API_NAME_CAMEL} API Test
# Tests ${API_NAME} integration with Istio Gateway and OPA authorization

set -e

echo "🔧 ${API_NAME_CAMEL} API Test (via Istio Gateway)"
echo "$(printf '=%.0s' {1..50})"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "\${BLUE}[INFO]\${NC} \$1"
}

print_success() {
    echo -e "\${GREEN}[SUCCESS]\${NC} \$1"
}

print_error() {
    echo -e "\${RED}[ERROR]\${NC} \$1"
}

# Test configuration
GATEWAY_HOST="opa-demo.local"
BASE_URL="http://localhost"
API_URL="\$BASE_URL/api/v1/${RESOURCE_NAME}"
HEALTH_URL="\$BASE_URL/${RESOURCE_NAME_SINGULAR}-health"

# Check if API is accessible
print_status "Checking ${API_NAME} health endpoint..."
if curl -s --connect-timeout 5 -H "Host: \$GATEWAY_HOST" "\$HEALTH_URL" > /dev/null; then
    print_success "✅ ${API_NAME_CAMEL} health endpoint is accessible"
else
    print_error "❌ ${API_NAME_CAMEL} health endpoint not accessible"
    echo "   Make sure ${API_NAME} is deployed and SSH tunnel is active"
    exit 1
fi

# Test unauthorized access
print_status "Testing unauthorized access..."
UNAUTH_RESPONSE=\$(curl -s -w "%{http_code}" -o /dev/null -H "Host: \$GATEWAY_HOST" "\$API_URL")

if [ "\$UNAUTH_RESPONSE" = "403" ]; then
    print_success "✅ Unauthorized access properly denied (HTTP 403)"
else
    print_error "❌ Expected 403 for unauthorized access, got HTTP \$UNAUTH_RESPONSE"
fi

# Test with authentication (if tokens are available)
if [ -n "\$EMPLOYEE_TOKEN" ]; then
    print_status "Testing employee access..."
    
    # Test GET request
    EMPLOYEE_GET=\$(curl -s -w "%{http_code}" -o /dev/null -H "Host: \$GATEWAY_HOST" -H "Authorization: Bearer \$EMPLOYEE_TOKEN" "\$API_URL")
    
    if [ "\$EMPLOYEE_GET" = "200" ]; then
        print_success "✅ Employee GET access allowed (HTTP 200)"
    else
        print_error "❌ Employee GET access failed (HTTP \$EMPLOYEE_GET)"
    fi
    
    # Test POST request (should be denied for CRUD template)
    EMPLOYEE_POST=\$(curl -s -w "%{http_code}" -o /dev/null -X POST -H "Host: \$GATEWAY_HOST" -H "Authorization: Bearer \$EMPLOYEE_TOKEN" -H "Content-Type: application/json" -d '{"name":"Test"}' "\$API_URL")
    
    if [ "\$EMPLOYEE_POST" = "403" ]; then
        print_success "✅ Employee POST access properly denied (HTTP 403)"
    else
        print_error "❌ Expected 403 for employee POST, got HTTP \$EMPLOYEE_POST"
    fi
fi

if [ -n "\$MANAGER_TOKEN" ]; then
    print_status "Testing manager access..."
    
    # Test GET request
    MANAGER_GET=\$(curl -s -w "%{http_code}" -o /dev/null -H "Host: \$GATEWAY_HOST" -H "Authorization: Bearer \$MANAGER_TOKEN" "\$API_URL")
    
    if [ "\$MANAGER_GET" = "200" ]; then
        print_success "✅ Manager GET access allowed (HTTP 200)"
    else
        print_error "❌ Manager GET access failed (HTTP \$MANAGER_GET)"
    fi
    
    # Test POST request
    MANAGER_POST=\$(curl -s -w "%{http_code}" -o /dev/null -X POST -H "Host: \$GATEWAY_HOST" -H "Authorization: Bearer \$MANAGER_TOKEN" -H "Content-Type: application/json" -d '{"name":"Test Manager Create"}' "\$API_URL")
    
    if [ "\$MANAGER_POST" = "201" ] || [ "\$MANAGER_POST" = "200" ] || [ "\$MANAGER_POST" = "400" ]; then
        print_success "✅ Manager POST access allowed (HTTP \$MANAGER_POST)"
    else
        print_error "❌ Manager POST access failed (HTTP \$MANAGER_POST)"
    fi
fi

print_status "📊 ${API_NAME_CAMEL} API Test Summary"
echo "================================="
print_success "✅ ${API_NAME_CAMEL} API integration test completed"

echo ""
echo "🎯 ${API_NAME_CAMEL} API Test Complete"
echo "$(printf '=%.0s' {1..50})"
EOF

chmod +x "$TEST_FILE"

print_success "✅ Created integration test: $TEST_FILE"

# 6. Update main test runner
print_status "6️⃣ Updating test runner..."

TEST_RUNNER="tests/run-all-tests.sh"
TEST_NAME=$(basename "$TEST_FILE")

# Add to TESTS array in run-all-tests.sh using awk for better compatibility
awk -v test="$TEST_NAME" '
/^TESTS=\(/ {
    in_array = 1
    print
    next
}
in_array && /^\)/ {
    print "    \"" test "\""
    print
    in_array = 0
    next
}
{print}
' "$TEST_RUNNER" > "${TEST_RUNNER}.tmp" && mv "${TEST_RUNNER}.tmp" "$TEST_RUNNER"

print_success "✅ Updated test runner with $TEST_NAME"

# 7. Generate language-specific template (if requested)
if [ -n "$LANGUAGE" ]; then
    print_status "7️⃣ Generating $LANGUAGE template..."
    
    TEMPLATE_DIR="templates/${API_NAME}"
    mkdir -p "$TEMPLATE_DIR"
    
    case $LANGUAGE in
        "python")
            cat > "$TEMPLATE_DIR/app.py" << EOF
from flask import Flask, jsonify, request
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "${API_NAME}"})

@app.route('/api/v1/${RESOURCE_NAME}', methods=['GET'])
def get_${RESOURCE_NAME}():
    # TODO: Implement business logic
    return jsonify({"${RESOURCE_NAME}": [], "count": 0})

@app.route('/api/v1/${RESOURCE_NAME}', methods=['POST'])
def create_${RESOURCE_NAME_SINGULAR}():
    # TODO: Implement business logic
    data = request.get_json()
    return jsonify({"${RESOURCE_NAME_SINGULAR}": data}), 201

@app.route('/api/v1/${RESOURCE_NAME}/<${RESOURCE_NAME_SINGULAR}_id>', methods=['GET'])
def get_${RESOURCE_NAME_SINGULAR}(${RESOURCE_NAME_SINGULAR}_id):
    # TODO: Implement business logic
    return jsonify({"${RESOURCE_NAME_SINGULAR}": {"id": ${RESOURCE_NAME_SINGULAR}_id}})

@app.route('/api/v1/${RESOURCE_NAME}/<${RESOURCE_NAME_SINGULAR}_id>', methods=['PUT'])
def update_${RESOURCE_NAME_SINGULAR}(${RESOURCE_NAME_SINGULAR}_id):
    # TODO: Implement business logic
    data = request.get_json()
    return jsonify({"${RESOURCE_NAME_SINGULAR}": data})

@app.route('/api/v1/${RESOURCE_NAME}/<${RESOURCE_NAME_SINGULAR}_id>', methods=['DELETE'])
def delete_${RESOURCE_NAME_SINGULAR}(${RESOURCE_NAME_SINGULAR}_id):
    # TODO: Implement business logic
    return '', 204

if __name__ == '__main__':
    port = int(os.environ.get('PORT', ${API_PORT}))
    app.run(host='0.0.0.0', port=port, debug=True)
EOF

            cat > "$TEMPLATE_DIR/requirements.txt" << EOF
Flask==2.3.3
gunicorn==21.2.0
EOF

            cat > "$TEMPLATE_DIR/Dockerfile" << EOF
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE ${API_PORT}

CMD ["gunicorn", "--bind", "0.0.0.0:${API_PORT}", "app:app"]
EOF
            ;;
            
        "go")
            cat > "$TEMPLATE_DIR/main.go" << EOF
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"

    "github.com/gorilla/mux"
)

type ${API_NAME_CAMEL} struct {
    ID   string \`json:"id"\`
    Name string \`json:"name"\`
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{
        "status":  "healthy",
        "service": "${API_NAME}",
    })
}

func get${API_NAME_CAMEL}Handler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    // TODO: Implement business logic
    json.NewEncoder(w).Encode(map[string]interface{}{
        "${RESOURCE_NAME}": []${API_NAME_CAMEL}{},
        "count":            0,
    })
}

func create${API_NAME_CAMEL}Handler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    
    var ${RESOURCE_NAME_SINGULAR} ${API_NAME_CAMEL}
    if err := json.NewDecoder(r.Body).Decode(&${RESOURCE_NAME_SINGULAR}); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    
    // TODO: Implement business logic
    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(map[string]interface{}{
        "${RESOURCE_NAME_SINGULAR}": ${RESOURCE_NAME_SINGULAR},
    })
}

func main() {
    r := mux.NewRouter()
    
    r.HandleFunc("/health", healthHandler).Methods("GET")
    r.HandleFunc("/api/v1/${RESOURCE_NAME}", get${API_NAME_CAMEL}Handler).Methods("GET")
    r.HandleFunc("/api/v1/${RESOURCE_NAME}", create${API_NAME_CAMEL}Handler).Methods("POST")
    
    port := os.Getenv("PORT")
    if port == "" {
        port = "${API_PORT}"
    }
    
    fmt.Printf("${API_NAME_CAMEL} API listening on port %s\n", port)
    log.Fatal(http.ListenAndServe(":"+port, r))
}
EOF

            cat > "$TEMPLATE_DIR/go.mod" << EOF
module ${API_NAME}

go 1.21

require github.com/gorilla/mux v1.8.0
EOF

            cat > "$TEMPLATE_DIR/Dockerfile" << EOF
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -o ${API_NAME} .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/

COPY --from=builder /app/${API_NAME} .

EXPOSE ${API_PORT}

CMD ["./${API_NAME}"]
EOF
            ;;
    esac
    
    print_success "✅ Generated $LANGUAGE template in $TEMPLATE_DIR"
fi

# 8. Summary and next steps
echo ""
print_success "🎉 Successfully added $API_NAME to the setup!"
echo ""
print_status "📋 Next Steps:"
echo "1. Build your API using the generated template (if created)"
echo "2. Build and push Docker image: docker build -t $API_NAME:latest ."
echo "3. Deploy with Helm: helm upgrade opa-keycloak helm/opa-keycloak --namespace opa-keycloak"
echo "4. Run tests: ./tests/run-all-tests.sh"
echo ""
print_status "📁 Files Created/Modified:"
echo "  - $HELM_TEMPLATE"
echo "  - $VALUES_FILE (updated)"
echo "  - $GATEWAY_FILE (updated)"
echo "  - $OPA_POLICY_FILE"
echo "  - $TEST_FILE"
if [ -n "$LANGUAGE" ]; then
    echo "  - $TEMPLATE_DIR/ (language template)"
fi
echo ""
print_status "🔧 Manual Steps Required:"
echo "1. Update the main OPA policy file to include the new policy rules"
echo "2. Add any new Keycloak roles if needed: ./scripts/setup-keycloak.sh"
echo "3. Review and customize the generated OPA policy for your specific needs"
echo ""
print_warning "⚠️  Remember to backup your files before deploying!" 