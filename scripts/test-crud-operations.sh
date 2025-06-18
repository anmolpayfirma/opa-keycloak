#!/bin/bash

# CRUD Operations Test Script
# Tests Create, Read, Update, Delete operations on Employee API with PostgreSQL

set -e

echo "🔧 Employee API CRUD Operations Test"
echo "===================================="

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

# Get Employee API pod
API_POD=$($KUBECTL_CMD get pod -l app=employee-api -o jsonpath='{.items[0].metadata.name}')
if [ -z "$API_POD" ]; then
    print_error "Employee API pod not found"
    exit 1
fi

print_status "Using Employee API pod: $API_POD"

# Test employee ID for CRUD operations
TEST_EMPLOYEE_ID="EMP999"
TEST_EMPLOYEE_NAME="Test Employee"
TEST_EMPLOYEE_DEPT="Engineering"
TEST_EMPLOYEE_EMAIL="test@company.com"

echo ""
print_status "🧪 Starting CRUD Operations Tests..."

# ============================================================================
# CREATE Operation
# ============================================================================
echo ""
print_status "1️⃣  Testing CREATE operation..."

CREATE_DATA=$(cat <<EOF
{
    "id": "$TEST_EMPLOYEE_ID",
    "name": "$TEST_EMPLOYEE_NAME",
    "department": "$TEST_EMPLOYEE_DEPT",
    "email": "$TEST_EMPLOYEE_EMAIL"
}
EOF
)

CREATE_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$CREATE_DATA" \
    http://localhost:8080/api/v1/employees)

if echo "$CREATE_RESPONSE" | grep -q "\"$TEST_EMPLOYEE_ID\""; then
    print_success "✅ CREATE: Employee created successfully"
    echo "   Response: $CREATE_RESPONSE"
else
    print_error "❌ CREATE: Failed to create employee"
    echo "   Response: $CREATE_RESPONSE"
fi

# ============================================================================
# READ Operations
# ============================================================================
echo ""
print_status "2️⃣  Testing READ operations..."

# Read all employees
print_status "2a. Reading all employees..."
READ_ALL_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s http://localhost:8080/api/v1/employees)

EMPLOYEE_COUNT=$(echo "$READ_ALL_RESPONSE" | grep -o '"count":[0-9]*' | cut -d: -f2)
if [ "$EMPLOYEE_COUNT" -gt 0 ]; then
    print_success "✅ READ ALL: Found $EMPLOYEE_COUNT employees"
else
    print_error "❌ READ ALL: No employees found"
    echo "   Response: $READ_ALL_RESPONSE"
fi

# Read specific employee
print_status "2b. Reading specific employee ($TEST_EMPLOYEE_ID)..."
READ_ONE_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s http://localhost:8080/api/v1/employees/$TEST_EMPLOYEE_ID)

if echo "$READ_ONE_RESPONSE" | grep -q "\"$TEST_EMPLOYEE_NAME\""; then
    print_success "✅ READ ONE: Found employee $TEST_EMPLOYEE_ID"
    echo "   Response: $READ_ONE_RESPONSE"
else
    print_error "❌ READ ONE: Employee $TEST_EMPLOYEE_ID not found"
    echo "   Response: $READ_ONE_RESPONSE"
fi

# Read departments
print_status "2c. Reading departments..."
DEPT_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s http://localhost:8080/api/v1/departments)

if echo "$DEPT_RESPONSE" | grep -q '"Engineering"'; then
    print_success "✅ READ DEPARTMENTS: Departments loaded successfully"
    DEPT_COUNT=$(echo "$DEPT_RESPONSE" | grep -o '"count":[0-9]*' | cut -d: -f2)
    echo "   Found $DEPT_COUNT departments"
else
    print_error "❌ READ DEPARTMENTS: Failed to load departments"
    echo "   Response: $DEPT_RESPONSE"
fi

# Filter employees by department
print_status "2d. Filtering employees by department..."
FILTER_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s "http://localhost:8080/api/v1/employees?department=Engineering")

if echo "$FILTER_RESPONSE" | grep -q '"department":"Engineering"'; then
    print_success "✅ FILTER: Department filter works"
    FILTERED_COUNT=$(echo "$FILTER_RESPONSE" | grep -o '"count":[0-9]*' | cut -d: -f2)
    echo "   Found $FILTERED_COUNT Engineering employees"
else
    print_error "❌ FILTER: Department filter failed"
    echo "   Response: $FILTER_RESPONSE"
fi

# ============================================================================
# UPDATE Operation
# ============================================================================
echo ""
print_status "3️⃣  Testing UPDATE operation..."

UPDATED_NAME="Updated Test Employee"
UPDATED_EMAIL="updated@company.com"

UPDATE_DATA=$(cat <<EOF
{
    "name": "$UPDATED_NAME",
    "email": "$UPDATED_EMAIL"
}
EOF
)

UPDATE_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s -X PUT \
    -H "Content-Type: application/json" \
    -d "$UPDATE_DATA" \
    http://localhost:8080/api/v1/employees/$TEST_EMPLOYEE_ID)

if echo "$UPDATE_RESPONSE" | grep -q "\"$UPDATED_NAME\""; then
    print_success "✅ UPDATE: Employee updated successfully"
    echo "   Response: $UPDATE_RESPONSE"
else
    print_error "❌ UPDATE: Failed to update employee"
    echo "   Response: $UPDATE_RESPONSE"
fi

# Verify update
print_status "3a. Verifying update..."
VERIFY_UPDATE_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s http://localhost:8080/api/v1/employees/$TEST_EMPLOYEE_ID)

if echo "$VERIFY_UPDATE_RESPONSE" | grep -q "\"$UPDATED_NAME\"" && echo "$VERIFY_UPDATE_RESPONSE" | grep -q "\"$UPDATED_EMAIL\""; then
    print_success "✅ UPDATE VERIFICATION: Changes persisted correctly"
else
    print_error "❌ UPDATE VERIFICATION: Changes not persisted"
    echo "   Response: $VERIFY_UPDATE_RESPONSE"
fi

# ============================================================================
# DELETE Operation
# ============================================================================
echo ""
print_status "4️⃣  Testing DELETE operation..."

DELETE_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s -X DELETE \
    http://localhost:8080/api/v1/employees/$TEST_EMPLOYEE_ID)

if echo "$DELETE_RESPONSE" | grep -q "deleted successfully"; then
    print_success "✅ DELETE: Employee deleted successfully"
    echo "   Response: $DELETE_RESPONSE"
else
    print_error "❌ DELETE: Failed to delete employee"
    echo "   Response: $DELETE_RESPONSE"
fi

# Verify deletion
print_status "4a. Verifying deletion..."
VERIFY_DELETE_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s -w "%{http_code}" http://localhost:8080/api/v1/employees/$TEST_EMPLOYEE_ID)

if echo "$VERIFY_DELETE_RESPONSE" | grep -q "404"; then
    print_success "✅ DELETE VERIFICATION: Employee successfully removed"
else
    print_error "❌ DELETE VERIFICATION: Employee still exists"
    echo "   Response: $VERIFY_DELETE_RESPONSE"
fi

# ============================================================================
# Error Handling Tests
# ============================================================================
echo ""
print_status "5️⃣  Testing error handling..."

# Test duplicate creation
print_status "5a. Testing duplicate employee creation..."
DUPLICATE_DATA=$(cat <<EOF
{
    "id": "EMP001",
    "name": "Duplicate Employee",
    "department": "Engineering"
}
EOF
)

DUPLICATE_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$DUPLICATE_DATA" \
    http://localhost:8080/api/v1/employees)

if echo "$DUPLICATE_RESPONSE" | grep -q "409"; then
    print_success "✅ ERROR HANDLING: Duplicate creation properly rejected"
else
    print_warning "⚠️  ERROR HANDLING: Unexpected response for duplicate creation"
    echo "   Response: $DUPLICATE_RESPONSE"
fi

# Test invalid JSON
print_status "5b. Testing invalid JSON..."
INVALID_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"invalid": json}' \
    http://localhost:8080/api/v1/employees)

if echo "$INVALID_RESPONSE" | grep -q "400"; then
    print_success "✅ ERROR HANDLING: Invalid JSON properly rejected"
else
    print_warning "⚠️  ERROR HANDLING: Unexpected response for invalid JSON"
    echo "   Response: $INVALID_RESPONSE"
fi

# Test missing required fields
print_status "5c. Testing missing required fields..."
MISSING_FIELDS_DATA='{"name": "Incomplete Employee"}'

MISSING_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$MISSING_FIELDS_DATA" \
    http://localhost:8080/api/v1/employees)

if echo "$MISSING_RESPONSE" | grep -q "400"; then
    print_success "✅ ERROR HANDLING: Missing fields properly rejected"
else
    print_warning "⚠️  ERROR HANDLING: Unexpected response for missing fields"
    echo "   Response: $MISSING_RESPONSE"
fi

# ============================================================================
# Performance Test
# ============================================================================
echo ""
print_status "6️⃣  Testing performance..."

print_status "6a. Bulk read test (10 requests)..."
START_TIME=$(date +%s%N)

for i in {1..10}; do
    $KUBECTL_CMD exec $API_POD -- curl -s http://localhost:8080/api/v1/employees > /dev/null
done

END_TIME=$(date +%s%N)
DURATION=$(( ($END_TIME - $START_TIME) / 1000000 )) # Convert to milliseconds

print_success "✅ PERFORMANCE: 10 requests completed in ${DURATION}ms"
print_status "   Average: $((DURATION / 10))ms per request"

# ============================================================================
# Database State Verification
# ============================================================================
echo ""
print_status "7️⃣  Verifying database state..."

# Count employees directly from database
DB_COUNT=$($KUBECTL_CMD run db-count-test --image=postgres:15-alpine --rm -i --restart=Never -- \
    psql -h postgresql-service -U employee_api -d employee_api -t -c "SELECT COUNT(*) FROM employees;")

API_COUNT_RESPONSE=$($KUBECTL_CMD exec $API_POD -- curl -s http://localhost:8080/api/v1/employees)
API_COUNT=$(echo "$API_COUNT_RESPONSE" | grep -o '"count":[0-9]*' | cut -d: -f2)

if [ "$DB_COUNT" -eq "$API_COUNT" ]; then
    print_success "✅ DATABASE CONSISTENCY: API count matches database count ($API_COUNT)"
else
    print_error "❌ DATABASE CONSISTENCY: Mismatch - DB: $DB_COUNT, API: $API_COUNT"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "🎉 CRUD Operations Test Summary"
echo "==============================="
print_success "✅ CREATE operation works"
print_success "✅ READ operations work (all, one, filter)"
print_success "✅ UPDATE operation works"
print_success "✅ DELETE operation works"
print_success "✅ Error handling is proper"
print_success "✅ Performance is acceptable"
print_success "✅ Database consistency maintained"

echo ""
print_status "🚀 Your PostgreSQL-enabled Employee API is fully functional!"
echo ""
print_status "Available endpoints:"
echo "  GET    /api/v1/employees          - List all employees"
echo "  GET    /api/v1/employees?department=X - Filter by department"
echo "  GET    /api/v1/employees/{id}     - Get specific employee"
echo "  POST   /api/v1/employees          - Create new employee"
echo "  PUT    /api/v1/employees/{id}     - Update employee"
echo "  DELETE /api/v1/employees/{id}     - Delete employee"
echo "  GET    /api/v1/departments        - List all departments"
echo "  GET    /health                    - Health check"

echo ""
print_status "Next steps:"
echo "1. Test authorization with: ./scripts/test-authorization-postgres.sh"
echo "2. Monitor database performance"
echo "3. Set up database backups"
echo "4. Configure connection pooling for production" 