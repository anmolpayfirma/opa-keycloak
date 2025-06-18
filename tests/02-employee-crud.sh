#!/bin/bash

# Employee CRUD Operations Test
# Tests Create, Read, Update, Delete operations on Employee API

set -e

echo "👥 Employee CRUD Operations Test"
echo "================================"

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
TEST_EMPLOYEE_ID="EMP999"
TEST_EMPLOYEE_NAME="Test Employee"
TEST_EMPLOYEE_DEPT="Engineering"
TEST_EMPLOYEE_EMAIL="test@company.com"

# Check if Employee API is accessible
print_status "Checking Employee API connectivity..."
if ! curl -s --connect-timeout 5 "$EMPLOYEE_API_URL/health" > /dev/null; then
    print_error "❌ Employee API is not accessible"
    echo "   Make sure port forwarding is active: kubectl port-forward service/employee-api-service 3000:8080 -n opa-keycloak"
    exit 1
fi

print_success "✅ Employee API is accessible"
echo ""

# ============================================================================
# CREATE Operation
# ============================================================================
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

CREATE_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$CREATE_DATA" \
    "$EMPLOYEE_API_URL/api/v1/employees")

if echo "$CREATE_RESPONSE" | jq -e ".employee.id" > /dev/null 2>&1 && echo "$CREATE_RESPONSE" | grep -q "$TEST_EMPLOYEE_ID"; then
    print_success "✅ CREATE: Employee created successfully"
    echo "   Employee ID: $(echo "$CREATE_RESPONSE" | jq -r '.employee.id')"
    echo "   Name: $(echo "$CREATE_RESPONSE" | jq -r '.employee.name')"
else
    print_error "❌ CREATE: Failed to create employee"
    echo "   Response: $CREATE_RESPONSE"
fi

echo ""

# ============================================================================
# READ Operations
# ============================================================================
print_status "2️⃣  Testing READ operations..."

# Read all employees
print_status "2a. Reading all employees..."
READ_ALL_RESPONSE=$(curl -s "$EMPLOYEE_API_URL/api/v1/employees")

if echo "$READ_ALL_RESPONSE" | jq -e ".count" > /dev/null 2>&1; then
    EMPLOYEE_COUNT=$(echo "$READ_ALL_RESPONSE" | jq -r '.count')
    if [ "$EMPLOYEE_COUNT" -gt 0 ]; then
        print_success "✅ READ ALL: Found $EMPLOYEE_COUNT employees"
    else
        print_warning "⚠️  READ ALL: No employees found"
    fi
else
    print_error "❌ READ ALL: Invalid response format"
    echo "   Response: $READ_ALL_RESPONSE"
fi

# Read specific employee
print_status "2b. Reading specific employee ($TEST_EMPLOYEE_ID)..."
READ_ONE_RESPONSE=$(curl -s "$EMPLOYEE_API_URL/api/v1/employees/$TEST_EMPLOYEE_ID")

if echo "$READ_ONE_RESPONSE" | jq -e ".employee.id" > /dev/null 2>&1 && echo "$READ_ONE_RESPONSE" | grep -q "$TEST_EMPLOYEE_NAME"; then
    print_success "✅ READ ONE: Found employee $TEST_EMPLOYEE_ID"
    echo "   Name: $(echo "$READ_ONE_RESPONSE" | jq -r '.employee.name')"
    echo "   Department: $(echo "$READ_ONE_RESPONSE" | jq -r '.employee.department')"
else
    print_error "❌ READ ONE: Employee $TEST_EMPLOYEE_ID not found"
    echo "   Response: $READ_ONE_RESPONSE"
fi

# Read departments
print_status "2c. Reading departments..."
DEPT_RESPONSE=$(curl -s "$EMPLOYEE_API_URL/api/v1/departments")

if echo "$DEPT_RESPONSE" | jq -e ".departments" > /dev/null 2>&1; then
    DEPT_COUNT=$(echo "$DEPT_RESPONSE" | jq -r '.count // (.departments | length)')
    print_success "✅ READ DEPARTMENTS: Found $DEPT_COUNT departments"
    echo "   Departments: $(echo "$DEPT_RESPONSE" | jq -r '.departments[]?' | tr '\n' ' ')"
else
    print_error "❌ READ DEPARTMENTS: Failed to load departments"
    echo "   Response: $DEPT_RESPONSE"
fi

# Filter employees by department
print_status "2d. Filtering employees by department..."
FILTER_RESPONSE=$(curl -s "$EMPLOYEE_API_URL/api/v1/employees?department=Engineering")

if echo "$FILTER_RESPONSE" | jq -e ".employees" > /dev/null 2>&1; then
    FILTERED_COUNT=$(echo "$FILTER_RESPONSE" | jq -r '.count // (.employees | length)')
    print_success "✅ FILTER: Found $FILTERED_COUNT Engineering employees"
else
    print_error "❌ FILTER: Department filter failed"
    echo "   Response: $FILTER_RESPONSE"
fi

echo ""

# ============================================================================
# UPDATE Operation
# ============================================================================
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

UPDATE_RESPONSE=$(curl -s -X PUT \
    -H "Content-Type: application/json" \
    -d "$UPDATE_DATA" \
    "$EMPLOYEE_API_URL/api/v1/employees/$TEST_EMPLOYEE_ID")

if echo "$UPDATE_RESPONSE" | jq -e ".employee.name" > /dev/null 2>&1 && echo "$UPDATE_RESPONSE" | grep -q "$UPDATED_NAME"; then
    print_success "✅ UPDATE: Employee updated successfully"
    echo "   New name: $(echo "$UPDATE_RESPONSE" | jq -r '.employee.name')"
    echo "   New email: $(echo "$UPDATE_RESPONSE" | jq -r '.employee.email')"
else
    print_error "❌ UPDATE: Failed to update employee"
    echo "   Response: $UPDATE_RESPONSE"
fi

# Verify update
print_status "3a. Verifying update..."
VERIFY_UPDATE_RESPONSE=$(curl -s "$EMPLOYEE_API_URL/api/v1/employees/$TEST_EMPLOYEE_ID")

if echo "$VERIFY_UPDATE_RESPONSE" | grep -q "$UPDATED_NAME" && echo "$VERIFY_UPDATE_RESPONSE" | grep -q "$UPDATED_EMAIL"; then
    print_success "✅ UPDATE VERIFICATION: Changes persisted correctly"
else
    print_error "❌ UPDATE VERIFICATION: Changes not persisted"
    echo "   Response: $VERIFY_UPDATE_RESPONSE"
fi

echo ""

# ============================================================================
# DELETE Operation
# ============================================================================
print_status "4️⃣  Testing DELETE operation..."

DELETE_RESPONSE=$(curl -s -X DELETE "$EMPLOYEE_API_URL/api/v1/employees/$TEST_EMPLOYEE_ID")

if echo "$DELETE_RESPONSE" | grep -qi "deleted\|success"; then
    print_success "✅ DELETE: Employee deleted successfully"
    echo "   Response: $DELETE_RESPONSE"
else
    print_warning "⚠️  DELETE: Unexpected response (may still have worked)"
    echo "   Response: $DELETE_RESPONSE"
fi

# Verify deletion
print_status "4a. Verifying deletion..."
VERIFY_DELETE_RESPONSE=$(curl -s "$EMPLOYEE_API_URL/api/v1/employees/$TEST_EMPLOYEE_ID")

if echo "$VERIFY_DELETE_RESPONSE" | grep -qi "not found\|error"; then
    print_success "✅ DELETE VERIFICATION: Employee successfully removed"
else
    print_error "❌ DELETE VERIFICATION: Employee still exists"
    echo "   Response: $VERIFY_DELETE_RESPONSE"
fi

echo ""
echo "🎯 CRUD Operations Test Complete"
echo "=================================" 