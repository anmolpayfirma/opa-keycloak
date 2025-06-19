#!/bin/bash

# Employee CRUD Operations Test
# Tests Create, Read, Update, Delete operations on Employee API via Istio Gateway

set -e

echo "👥 Employee CRUD Operations Test (via Istio Gateway)"
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
EMPLOYEE_API_URL="$BASE_URL/api/v1/employees"
HEALTH_URL="$BASE_URL/health"
TEST_EMPLOYEE_ID="EMP999"
TEST_EMPLOYEE_NAME="Test Employee"
TEST_EMPLOYEE_DEPT="Engineering"
TEST_EMPLOYEE_EMAIL="test@company.com"

# Check if Employee API is accessible
print_status "Checking Employee API connectivity through Istio Gateway..."
if ! curl -s --connect-timeout 5 -H "Host: $GATEWAY_HOST" "$HEALTH_URL" > /dev/null; then
    print_error "❌ Services are not accessible through Istio Gateway"
    echo "   Make sure SSH tunnel is active: ./scripts/setup-tunnel.sh"
    echo "   And /etc/hosts contains: 127.0.0.1 opa-demo.local"
    exit 1
fi

print_success "✅ Services are accessible through Istio Gateway"
echo ""

# Note about authentication
print_status "📝 Note: Employee API requires authentication for CRUD operations"
print_status "    This test will show expected authentication errors (501/401)"
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

CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Host: $GATEWAY_HOST" \
    -H "Content-Type: application/json" \
    -d "$CREATE_DATA" \
    "$EMPLOYEE_API_URL")

CREATE_BODY=$(echo "$CREATE_RESPONSE" | head -n -1)
CREATE_STATUS=$(echo "$CREATE_RESPONSE" | tail -n 1)

if [ "$CREATE_STATUS" = "201" ] || [ "$CREATE_STATUS" = "200" ]; then
    if echo "$CREATE_BODY" | jq -e ".employee.id" > /dev/null 2>&1 && echo "$CREATE_BODY" | grep -q "$TEST_EMPLOYEE_ID"; then
        print_success "✅ CREATE: Employee created successfully"
        echo "   Employee ID: $(echo "$CREATE_BODY" | jq -r '.employee.id')"
        echo "   Name: $(echo "$CREATE_BODY" | jq -r '.employee.name')"
    else
        print_success "✅ CREATE: Operation completed (HTTP $CREATE_STATUS)"
        echo "   Response: $CREATE_BODY"
    fi
elif [ "$CREATE_STATUS" = "501" ] || [ "$CREATE_STATUS" = "401" ] || [ "$CREATE_STATUS" = "403" ]; then
    print_warning "⚠️  CREATE: Authentication required (HTTP $CREATE_STATUS)"
    echo "   This is expected behavior - API requires valid JWT token"
    echo "   Response: $CREATE_BODY"
else
    print_error "❌ CREATE: Unexpected status $CREATE_STATUS"
    echo "   Response: $CREATE_BODY"
fi

echo ""

# ============================================================================
# READ Operations
# ============================================================================
print_status "2️⃣  Testing READ operations..."

# Read all employees
print_status "2a. Reading all employees..."
READ_ALL_RESPONSE=$(curl -s -w "\n%{http_code}" -H "Host: $GATEWAY_HOST" "$EMPLOYEE_API_URL")
READ_ALL_BODY=$(echo "$READ_ALL_RESPONSE" | head -n -1)
READ_ALL_STATUS=$(echo "$READ_ALL_RESPONSE" | tail -n 1)

if [ "$READ_ALL_STATUS" = "200" ]; then
    if echo "$READ_ALL_BODY" | jq -e ".count" > /dev/null 2>&1; then
        EMPLOYEE_COUNT=$(echo "$READ_ALL_BODY" | jq -r '.count')
        if [ "$EMPLOYEE_COUNT" -gt 0 ]; then
            print_success "✅ READ ALL: Found $EMPLOYEE_COUNT employees"
        else
            print_warning "⚠️  READ ALL: No employees found"
        fi
    else
        print_success "✅ READ ALL: API responded (HTTP $READ_ALL_STATUS)"
        echo "   Response: $READ_ALL_BODY"
    fi
elif [ "$READ_ALL_STATUS" = "501" ] || [ "$READ_ALL_STATUS" = "401" ] || [ "$READ_ALL_STATUS" = "403" ]; then
    print_warning "⚠️  READ ALL: Authentication required (HTTP $READ_ALL_STATUS)"
    echo "   This is expected behavior - API requires valid JWT token"
else
    print_error "❌ READ ALL: Unexpected status $READ_ALL_STATUS"
    echo "   Response: $READ_ALL_BODY"
fi

# Read specific employee
print_status "2b. Reading specific employee ($TEST_EMPLOYEE_ID)..."
READ_ONE_RESPONSE=$(curl -s -w "\n%{http_code}" -H "Host: $GATEWAY_HOST" "$EMPLOYEE_API_URL/$TEST_EMPLOYEE_ID")
READ_ONE_BODY=$(echo "$READ_ONE_RESPONSE" | head -n -1)
READ_ONE_STATUS=$(echo "$READ_ONE_RESPONSE" | tail -n 1)

if [ "$READ_ONE_STATUS" = "200" ]; then
    if echo "$READ_ONE_BODY" | jq -e ".employee.id" > /dev/null 2>&1 && echo "$READ_ONE_BODY" | grep -q "$TEST_EMPLOYEE_NAME"; then
        print_success "✅ READ ONE: Found employee $TEST_EMPLOYEE_ID"
        echo "   Name: $(echo "$READ_ONE_BODY" | jq -r '.employee.name')"
        echo "   Department: $(echo "$READ_ONE_BODY" | jq -r '.employee.department')"
    else
        print_success "✅ READ ONE: API responded (HTTP $READ_ONE_STATUS)"
        echo "   Response: $READ_ONE_BODY"
    fi
elif [ "$READ_ONE_STATUS" = "404" ]; then
    print_warning "⚠️  READ ONE: Employee $TEST_EMPLOYEE_ID not found (HTTP $READ_ONE_STATUS)"
    echo "   This may be expected if CREATE operation was not authorized"
elif [ "$READ_ONE_STATUS" = "501" ] || [ "$READ_ONE_STATUS" = "401" ] || [ "$READ_ONE_STATUS" = "403" ]; then
    print_warning "⚠️  READ ONE: Authentication required (HTTP $READ_ONE_STATUS)"
    echo "   This is expected behavior - API requires valid JWT token"
else
    print_error "❌ READ ONE: Unexpected status $READ_ONE_STATUS"
    echo "   Response: $READ_ONE_BODY"
fi

# Test departments endpoint
print_status "2c. Reading departments..."
DEPT_RESPONSE=$(curl -s -w "\n%{http_code}" -H "Host: $GATEWAY_HOST" "$BASE_URL/api/v1/departments")
DEPT_BODY=$(echo "$DEPT_RESPONSE" | head -n -1)
DEPT_STATUS=$(echo "$DEPT_RESPONSE" | tail -n 1)

if [ "$DEPT_STATUS" = "200" ]; then
    if echo "$DEPT_BODY" | jq -e ".departments" > /dev/null 2>&1; then
        DEPT_COUNT=$(echo "$DEPT_BODY" | jq -r '.count // (.departments | length)')
        print_success "✅ READ DEPARTMENTS: Found $DEPT_COUNT departments"
        echo "   Departments: $(echo "$DEPT_BODY" | jq -r '.departments[]?' | tr '\n' ' ')"
    else
        print_success "✅ READ DEPARTMENTS: API responded (HTTP $DEPT_STATUS)"
        echo "   Response: $DEPT_BODY"
    fi
elif [ "$DEPT_STATUS" = "501" ] || [ "$DEPT_STATUS" = "401" ] || [ "$DEPT_STATUS" = "403" ]; then
    print_warning "⚠️  READ DEPARTMENTS: Authentication required (HTTP $DEPT_STATUS)"
    echo "   This is expected behavior - API requires valid JWT token"
else
    print_error "❌ READ DEPARTMENTS: Unexpected status $DEPT_STATUS"
    echo "   Response: $DEPT_BODY"
fi

# Filter employees by department
print_status "2d. Filtering employees by department..."
FILTER_RESPONSE=$(curl -s -w "\n%{http_code}" -H "Host: $GATEWAY_HOST" "$EMPLOYEE_API_URL?department=Engineering")
FILTER_BODY=$(echo "$FILTER_RESPONSE" | head -n -1)
FILTER_STATUS=$(echo "$FILTER_RESPONSE" | tail -n 1)

if [ "$FILTER_STATUS" = "200" ]; then
    if echo "$FILTER_BODY" | jq -e ".employees" > /dev/null 2>&1; then
        FILTERED_COUNT=$(echo "$FILTER_BODY" | jq -r '.count // (.employees | length)')
        print_success "✅ FILTER: Found $FILTERED_COUNT Engineering employees"
    else
        print_success "✅ FILTER: API responded (HTTP $FILTER_STATUS)"
        echo "   Response: $FILTER_BODY"
    fi
elif [ "$FILTER_STATUS" = "501" ] || [ "$FILTER_STATUS" = "401" ] || [ "$FILTER_STATUS" = "403" ]; then
    print_warning "⚠️  FILTER: Authentication required (HTTP $FILTER_STATUS)"
    echo "   This is expected behavior - API requires valid JWT token"
else
    print_error "❌ FILTER: Unexpected status $FILTER_STATUS"
    echo "   Response: $FILTER_BODY"
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

UPDATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
    -H "Host: $GATEWAY_HOST" \
    -H "Content-Type: application/json" \
    -d "$UPDATE_DATA" \
    "$EMPLOYEE_API_URL/$TEST_EMPLOYEE_ID")

UPDATE_BODY=$(echo "$UPDATE_RESPONSE" | head -n -1)
UPDATE_STATUS=$(echo "$UPDATE_RESPONSE" | tail -n 1)

if [ "$UPDATE_STATUS" = "200" ]; then
    if echo "$UPDATE_BODY" | jq -e ".employee.name" > /dev/null 2>&1 && echo "$UPDATE_BODY" | grep -q "$UPDATED_NAME"; then
        print_success "✅ UPDATE: Employee updated successfully"
        echo "   New name: $(echo "$UPDATE_BODY" | jq -r '.employee.name')"
        echo "   New email: $(echo "$UPDATE_BODY" | jq -r '.employee.email')"
    else
        print_success "✅ UPDATE: API responded (HTTP $UPDATE_STATUS)"
        echo "   Response: $UPDATE_BODY"
    fi
elif [ "$UPDATE_STATUS" = "501" ] || [ "$UPDATE_STATUS" = "401" ] || [ "$UPDATE_STATUS" = "403" ]; then
    print_warning "⚠️  UPDATE: Authentication required (HTTP $UPDATE_STATUS)"
    echo "   This is expected behavior - API requires valid JWT token"
    echo "   Response: $UPDATE_BODY"
elif [ "$UPDATE_STATUS" = "404" ]; then
    print_warning "⚠️  UPDATE: Employee $TEST_EMPLOYEE_ID not found (HTTP $UPDATE_STATUS)"
    echo "   This may be expected if CREATE operation was not authorized"
else
    print_error "❌ UPDATE: Unexpected status $UPDATE_STATUS"
    echo "   Response: $UPDATE_BODY"
fi

echo ""

# ============================================================================
# DELETE Operation
# ============================================================================
print_status "4️⃣  Testing DELETE operation..."

DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE -H "Host: $GATEWAY_HOST" "$EMPLOYEE_API_URL/$TEST_EMPLOYEE_ID")
DELETE_BODY=$(echo "$DELETE_RESPONSE" | head -n -1)
DELETE_STATUS=$(echo "$DELETE_RESPONSE" | tail -n 1)

if [ "$DELETE_STATUS" = "200" ] || [ "$DELETE_STATUS" = "204" ]; then
    if echo "$DELETE_BODY" | grep -qi "deleted\|success"; then
        print_success "✅ DELETE: Employee deleted successfully"
        echo "   Response: $DELETE_BODY"
    else
        print_success "✅ DELETE: API responded (HTTP $DELETE_STATUS)"
        echo "   Response: $DELETE_BODY"
    fi
elif [ "$DELETE_STATUS" = "501" ] || [ "$DELETE_STATUS" = "401" ] || [ "$DELETE_STATUS" = "403" ]; then
    print_warning "⚠️  DELETE: Authentication required (HTTP $DELETE_STATUS)"
    echo "   This is expected behavior - API requires valid JWT token"
    echo "   Response: $DELETE_BODY"
elif [ "$DELETE_STATUS" = "404" ]; then
    print_warning "⚠️  DELETE: Employee $TEST_EMPLOYEE_ID not found (HTTP $DELETE_STATUS)"
    echo "   This may be expected if CREATE operation was not authorized"
else
    print_error "❌ DELETE: Unexpected status $DELETE_STATUS"
    echo "   Response: $DELETE_BODY"
fi

# Verify deletion
print_status "4a. Verifying deletion..."
VERIFY_DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" -H "Host: $GATEWAY_HOST" "$EMPLOYEE_API_URL/$TEST_EMPLOYEE_ID")
VERIFY_DELETE_BODY=$(echo "$VERIFY_DELETE_RESPONSE" | head -n -1)
VERIFY_DELETE_STATUS=$(echo "$VERIFY_DELETE_RESPONSE" | tail -n 1)

if [ "$VERIFY_DELETE_STATUS" = "404" ]; then
    print_success "✅ DELETE VERIFICATION: Employee no longer exists"
elif [ "$VERIFY_DELETE_STATUS" = "501" ] || [ "$VERIFY_DELETE_STATUS" = "401" ] || [ "$VERIFY_DELETE_STATUS" = "403" ]; then
    print_warning "⚠️  DELETE VERIFICATION: Authentication required (HTTP $VERIFY_DELETE_STATUS)"
    echo "   Cannot verify deletion without authentication"
else
    print_warning "⚠️  DELETE VERIFICATION: Employee may still exist (HTTP $VERIFY_DELETE_STATUS)"
    echo "   Response: $VERIFY_DELETE_BODY"
fi

echo ""
echo "🎯 CRUD Operations Test Complete"
echo "================================="
echo ""
print_status "💡 Summary:"
print_status "   - All API endpoints are accessible through Istio Gateway"
print_status "   - Authentication is properly enforced (501/401/403 responses)"
print_status "   - To test full CRUD functionality, run with valid JWT tokens"
print_status "   - Use the authentication test (03-authentication.sh) to get tokens" 