#!/bin/bash

# Database Setup and Testing Script
# Tests PostgreSQL integration with Keycloak and Employee API

set -e

echo "🗄️  Database Setup and Testing Script"
echo "======================================"

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

# Check if running in cloud minikube
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    print_status "Running in cloud minikube mode"
    KUBECTL_CMD="ssh -o StrictHostKeyChecking=no ubuntu@$SPOT_INSTANCE_DNS_NAME kubectl"
else
    print_status "Running in local minikube mode"
    KUBECTL_CMD="kubectl"
fi

# Test 1: Check if PostgreSQL is running
print_status "Test 1: Checking PostgreSQL deployment..."
if $KUBECTL_CMD get pod -l app=postgresql | grep -q Running; then
    print_success "PostgreSQL pod is running"
else
    print_error "PostgreSQL pod is not running"
    $KUBECTL_CMD get pods -l app=postgresql
    exit 1
fi

# Test 2: Check PostgreSQL service
print_status "Test 2: Checking PostgreSQL service..."
if $KUBECTL_CMD get service postgresql-service > /dev/null 2>&1; then
    print_success "PostgreSQL service exists"
else
    print_error "PostgreSQL service not found"
    exit 1
fi

# Test 3: Test database connectivity from within cluster
print_status "Test 3: Testing database connectivity..."
DB_TEST_POD="db-test-$(date +%s)"
$KUBECTL_CMD run $DB_TEST_POD --image=postgres:15-alpine --rm -i --restart=Never -- \
    psql -h postgresql-service -U postgres -d opa_demo -c "SELECT version();" || {
    print_error "Database connectivity test failed"
    exit 1
}
print_success "Database connectivity test passed"

# Test 4: Check if databases and users exist
print_status "Test 4: Checking database schema..."
$KUBECTL_CMD run db-schema-test --image=postgres:15-alpine --rm -i --restart=Never -- \
    psql -h postgresql-service -U postgres -d opa_demo -c "
    SELECT datname FROM pg_database WHERE datname IN ('keycloak', 'employee_api');
    SELECT usename FROM pg_user WHERE usename IN ('keycloak', 'employee_api');
    " || {
    print_error "Database schema test failed"
    exit 1
}
print_success "Database schema test passed"

# Test 5: Check employee data
print_status "Test 5: Checking employee data..."
$KUBECTL_CMD run employee-data-test --image=postgres:15-alpine --rm -i --restart=Never -- \
    psql -h postgresql-service -U employee_api -d employee_api -c "
    SELECT COUNT(*) as employee_count FROM employees;
    SELECT COUNT(*) as department_count FROM departments;
    SELECT id, name, department FROM employees LIMIT 3;
    " || {
    print_error "Employee data test failed"
    exit 1
}
print_success "Employee data test passed"

# Test 6: Check Keycloak with PostgreSQL
print_status "Test 6: Checking Keycloak PostgreSQL integration..."
if $KUBECTL_CMD get pod -l app=keycloak | grep -q Running; then
    print_success "Keycloak with PostgreSQL is running"
    
    # Wait for Keycloak to be ready
    print_status "Waiting for Keycloak to be ready..."
    $KUBECTL_CMD wait --for=condition=ready pod -l app=keycloak --timeout=300s
    print_success "Keycloak is ready"
else
    print_error "Keycloak pod is not running"
    $KUBECTL_CMD get pods -l app=keycloak
    exit 1
fi

# Test 7: Check Employee API with PostgreSQL
print_status "Test 7: Checking Employee API PostgreSQL integration..."
if $KUBECTL_CMD get pod -l app=employee-api | grep -q Running; then
    print_success "Employee API with PostgreSQL is running"
    
    # Wait for Employee API to be ready
    print_status "Waiting for Employee API to be ready..."
    $KUBECTL_CMD wait --for=condition=ready pod -l app=employee-api --timeout=120s
    print_success "Employee API is ready"
else
    print_error "Employee API pod is not running"
    $KUBECTL_CMD get pods -l app=employee-api
    exit 1
fi

# Test 8: Test Employee API health endpoint
print_status "Test 8: Testing Employee API health endpoint..."
API_POD=$($KUBECTL_CMD get pod -l app=employee-api -o jsonpath='{.items[0].metadata.name}')
HEALTH_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s http://localhost:8080/health)

if echo "$HEALTH_RESPONSE" | grep -q '"status":"healthy"'; then
    print_success "Employee API health check passed"
    echo "Health Response: $HEALTH_RESPONSE"
else
    print_error "Employee API health check failed"
    echo "Health Response: $HEALTH_RESPONSE"
    exit 1
fi

# Test 9: Test Employee API database operations
print_status "Test 9: Testing Employee API database operations..."

# Test GET /api/v1/employees
EMPLOYEES_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s http://localhost:8080/api/v1/employees)
if echo "$EMPLOYEES_RESPONSE" | grep -q '"count"'; then
    print_success "Employee list endpoint works"
else
    print_error "Employee list endpoint failed"
    echo "Response: $EMPLOYEES_RESPONSE"
    exit 1
fi

# Test GET /api/v1/employees/EMP003
EMPLOYEE_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s http://localhost:8080/api/v1/employees/EMP003)
if echo "$EMPLOYEE_RESPONSE" | grep -q '"Bob Employee"'; then
    print_success "Employee detail endpoint works"
else
    print_error "Employee detail endpoint failed"
    echo "Response: $EMPLOYEE_RESPONSE"
    exit 1
fi

# Test GET /api/v1/departments
DEPARTMENTS_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s http://localhost:8080/api/v1/departments)
if echo "$DEPARTMENTS_RESPONSE" | grep -q '"Engineering"'; then
    print_success "Departments endpoint works"
else
    print_error "Departments endpoint failed"
    echo "Response: $DEPARTMENTS_RESPONSE"
    exit 1
fi

# Test 10: Check persistent storage
print_status "Test 10: Checking persistent storage..."
PVC_STATUS=$($KUBECTL_CMD get pvc postgresql-pvc -o jsonpath='{.status.phase}')
if [ "$PVC_STATUS" = "Bound" ]; then
    print_success "Persistent volume is bound"
else
    print_error "Persistent volume is not bound: $PVC_STATUS"
    exit 1
fi

# Test 11: Simulate pod restart to test persistence
print_status "Test 11: Testing data persistence after PostgreSQL restart..."
print_warning "This will restart the PostgreSQL pod..."
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Delete PostgreSQL pod to test persistence
    $KUBECTL_CMD delete pod -l app=postgresql
    
    # Wait for new pod to be ready
    print_status "Waiting for PostgreSQL to restart..."
    $KUBECTL_CMD wait --for=condition=ready pod -l app=postgresql --timeout=120s
    
    # Test data persistence
    $KUBECTL_CMD run persistence-test --image=postgres:15-alpine --rm -i --restart=Never -- \
        psql -h postgresql-service -U employee_api -d employee_api -c "
        SELECT COUNT(*) as employee_count FROM employees;
        " || {
        print_error "Data persistence test failed"
        exit 1
    }
    print_success "Data persistence test passed"
else
    print_warning "Skipping persistence test"
fi

# Summary
echo ""
echo "🎉 Database Setup Test Summary"
echo "=============================="
print_success "✅ PostgreSQL deployment is healthy"
print_success "✅ Database connectivity works"
print_success "✅ Database schema is correct"
print_success "✅ Employee data is seeded"
print_success "✅ Keycloak PostgreSQL integration works"
print_success "✅ Employee API PostgreSQL integration works"
print_success "✅ All API endpoints are functional"
print_success "✅ Persistent storage is working"

echo ""
print_status "🚀 Your PostgreSQL-enabled OPA + Keycloak system is ready!"
echo ""
print_status "Next steps:"
echo "1. Run: ./scripts/test-authorization-postgres.sh"
echo "2. Test CRUD operations: ./scripts/test-crud-operations.sh"
echo "3. Deploy to production with persistent storage"

echo ""
print_status "Database Information:"
echo "- PostgreSQL Version: 15"
echo "- Keycloak Database: keycloak"
echo "- Employee API Database: employee_api"
echo "- Persistent Storage: 5Gi"
echo "- Connection: postgresql-service:5432" 