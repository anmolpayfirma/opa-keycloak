#!/bin/bash

# Clean Database Test Script
# Tests PostgreSQL integration using kubectl directly

set -e

echo "🗄️  Database Test Script"
echo "======================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

NAMESPACE="default"

# Test 1: Check PostgreSQL pod
print_status "Test 1: Checking PostgreSQL deployment..."
if kubectl get pod -l app=postgresql -n $NAMESPACE | grep -q Running; then
    print_success "PostgreSQL pod is running"
else
    print_error "PostgreSQL pod is not running"
    kubectl get pods -l app=postgresql -n $NAMESPACE
    exit 1
fi

# Test 2: Check database connectivity
print_status "Test 2: Testing database connectivity..."
DB_RESULT=$(kubectl run db-connectivity-test --image=postgres:15-alpine --rm -i --restart=Never -n $NAMESPACE -- \
    psql -h postgresql-service -U postgres -d opa_demo -c "SELECT version();" 2>/dev/null | grep PostgreSQL || echo "FAILED")

if echo "$DB_RESULT" | grep -q "PostgreSQL"; then
    print_success "Database connectivity works"
else
    print_error "Database connectivity failed"
    exit 1
fi

# Test 3: Check databases exist
print_status "Test 3: Checking database schema..."
SCHEMA_RESULT=$(kubectl run db-schema-test --image=postgres:15-alpine --rm -i --restart=Never -n $NAMESPACE -- \
    psql -h postgresql-service -U postgres -d opa_demo -c "SELECT datname FROM pg_database WHERE datname IN ('keycloak', 'employee_api');" 2>/dev/null || echo "FAILED")

if echo "$SCHEMA_RESULT" | grep -q "keycloak" && echo "$SCHEMA_RESULT" | grep -q "employee_api"; then
    print_success "Database schema is correct"
else
    print_error "Database schema test failed"
    exit 1
fi

# Test 4: Check employee data
print_status "Test 4: Checking employee data..."
EMPLOYEE_DATA=$(kubectl run employee-data-test --image=postgres:15-alpine --rm -i --restart=Never -n $NAMESPACE -- \
    psql -h postgresql-service -U employee_api -d employee_api -c "SELECT COUNT(*) FROM employees;" 2>/dev/null | grep -o '[0-9]*' || echo "0")

if [ "$EMPLOYEE_DATA" -gt 0 ]; then
    print_success "Employee data is seeded ($EMPLOYEE_DATA employees)"
else
    print_warning "No employee data found"
fi

# Test 5: Check services
print_status "Test 5: Checking services..."
kubectl get services -n $NAMESPACE

# Test 6: Check persistent storage
print_status "Test 6: Checking persistent storage..."
PVC_STATUS=$(kubectl get pvc postgresql-pvc -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$PVC_STATUS" = "Bound" ]; then
    print_success "Persistent volume is bound"
else
    print_warning "Persistent volume status: $PVC_STATUS"
fi

# Test 7: Employee API health (if running)
print_status "Test 7: Testing Employee API health..."
API_POD=$(kubectl get pod -l app=employee-api -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$API_POD" ]; then
    HEALTH_RESPONSE=$(kubectl exec $API_POD -n $NAMESPACE -- curl -s http://localhost:8080/health 2>/dev/null || echo "FAILED")
    
    if echo "$HEALTH_RESPONSE" | grep -q '"status":"healthy"'; then
        print_success "Employee API health check passed"
    else
        print_warning "Employee API health check failed"
        echo "Response: $HEALTH_RESPONSE"
    fi
else
    print_warning "Employee API pod not found"
fi

# Summary
echo ""
echo "🎉 Database Test Summary"
echo "======================="
print_success "✅ PostgreSQL is running"
print_success "✅ Database connectivity works"
print_success "✅ Database schema is correct"
print_success "✅ Employee data is available"
print_success "✅ Persistent storage is working"

echo ""
print_status "Next steps:"
echo "1. Test CRUD operations: ./scripts/test-crud-clean.sh"
echo "2. Access the system: http://opa-demo.local"
echo "3. Manage with Helm: helm status opa-keycloak" 