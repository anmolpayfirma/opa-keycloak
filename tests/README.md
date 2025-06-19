# OPA-Keycloak Test Suite

This directory contains comprehensive tests for the OPA-Keycloak authorization system using Istio Gateway and curl-based testing.

## Test Structure

```
tests/
├── README.md                 # This file
├── run-all-tests.sh         # Master test runner
├── 01-basic-connectivity.sh # Service connectivity tests
├── 02-employee-crud.sh      # Employee API CRUD operations
└── 03-authentication.sh     # Keycloak authentication & OPA authorization tests
```

## Prerequisites

1. **Services deployed**: Run `./scripts/helm-deploy-istio.sh` first
2. **SSH tunnel active**: Run `./scripts/setup-tunnel.sh`
3. **Required tools**:
   - `kubectl` - Kubernetes CLI
   - `curl` - HTTP client
   - `jq` - JSON processor
   - `bash` - Shell (version 4+ recommended)
4. **Host configuration**: Add `127.0.0.1 opa-demo.local` to `/etc/hosts`

## Running Tests

### Run All Tests (Recommended)
```bash
# Run complete test suite
./tests/run-all-tests.sh
```

This script will:
- Check prerequisites and service status
- Verify Istio Gateway configuration
- Run all tests in sequence through Istio Gateway
- Provide comprehensive test results and summary

### Run Individual Tests

Make sure SSH tunnel is active:
```bash
# Set up SSH tunnel (in separate terminal)
./scripts/setup-tunnel.sh
```

Then run individual tests:
```bash
# Test service connectivity through Istio Gateway
./tests/01-basic-connectivity.sh

# Test CRUD operations through Istio Gateway
./tests/02-employee-crud.sh

# Test authentication & authorization (comprehensive)
./tests/03-authentication.sh
```

## Test Details

### 1. Basic Connectivity Test (`01-basic-connectivity.sh`)
- ✅ Health endpoint accessibility
- ✅ Employee API accessibility through Istio Gateway
- ✅ Keycloak accessibility through Istio Gateway
- ✅ Employee data availability
- ✅ Service response validation

**Expected Output:**
```
🔗 Basic Connectivity Test (via Istio Gateway)
===============================================
[SUCCESS] ✅ Health endpoint is accessible
[SUCCESS] ✅ Employee API is accessible through Istio Gateway
[SUCCESS] ✅ Keycloak is accessible through Istio Gateway
[SUCCESS] ✅ Employee data is available (6 employees found)
```

### 2. Employee CRUD Test (`02-employee-crud.sh`)
- ✅ CREATE: Add new employee via Istio Gateway
- ✅ READ: Get all employees, specific employee, departments
- ✅ UPDATE: Modify employee data
- ✅ DELETE: Remove employee
- ✅ FILTER: Department-based filtering
- ✅ ERROR: Invalid request handling

**Expected Output:**
```
👥 Employee CRUD Operations Test (via Istio Gateway)
====================================================
[SUCCESS] ✅ CREATE: Employee created successfully (HTTP 201)
[SUCCESS] ✅ READ ALL: Found 7 employees
[SUCCESS] ✅ READ SPECIFIC: Employee EMP999 found
[SUCCESS] ✅ UPDATE: Employee updated successfully (HTTP 200)
[SUCCESS] ✅ DELETE: Employee deleted successfully (HTTP 200)
```

### 3. Authentication & Authorization Test (`03-authentication.sh`)
**Comprehensive testing of the complete auth flow:**

#### Authentication Tests:
- ✅ Keycloak realm configuration validation
- ✅ JWT token generation for multiple users
- ✅ Token payload decoding and validation
- ✅ Token refresh functionality

#### Authorization Tests:
- ✅ **Unauthorized access** (no token) → 403 Forbidden
- ✅ **Employee role** (bob.employee):
  - GET requests → 200 OK (allowed)
  - POST/PUT/DELETE → 403 Forbidden (denied by OPA)
- ✅ **Manager role** (alice.manager):
  - GET requests → 200 OK (allowed)
  - POST/PUT/DELETE → 201/200/404 (allowed by OPA)
- ✅ **Health endpoint** → 200 OK (always accessible)

#### OPA Integration Tests:
- ✅ OPA decision logging verification
- ✅ Policy evaluation metrics
- ✅ Performance measurement

**Setup Required:**
```bash
# Deploy with Istio and OPA integration
./scripts/helm-deploy-istio.sh

# Configure Keycloak users and realm
./scripts/setup-keycloak.sh

# Start SSH tunnel for access
./scripts/setup-tunnel.sh
```

**Expected Output:**
```
🔐 Authentication & Authorization Test (Istio + OPA)
====================================================
[SUCCESS] ✅ Realm 'employee-management' is configured
[SUCCESS] ✅ Authentication successful for alice.manager
[SUCCESS] ✅ Authentication successful for bob.employee

3️⃣  Testing unauthorized access (no token)...
[SUCCESS] ✅ PASS: Health check without auth (HTTP 200)
[SUCCESS] ✅ PASS: Employee API without auth (HTTP 403)

4️⃣  Testing employee authorization (bob.employee)...
[SUCCESS] ✅ PASS: Employee GET request (HTTP 200)
[SUCCESS] ✅ PASS: Employee POST request (should be denied) (HTTP 403)

5️⃣  Testing manager authorization (alice.manager)...
[SUCCESS] ✅ PASS: Manager GET request (HTTP 200)
[SUCCESS] ✅ PASS: Manager POST request (HTTP 201 - Authorization successful)

📊 Test Summary
===============
Total Tests: 15
Passed: 15
Failed: 0
🎉 All tests passed! Authentication and authorization working perfectly.
```

## Architecture Under Test

The tests validate this complete architecture:

```
Client Request
     ↓
Istio Gateway (opa-demo.local)
     ↓
Istio VirtualService Routing
     ↓
┌─────────────────────────────────────┐
│  Employee API Pod                   │
│  ┌─────────────────────────────────┐│
│  │ Istio Sidecar (Envoy)          ││
│  │   ↓                            ││
│  │ OPA-Envoy (gRPC Authorization) ││
│  │   ↓                            ││
│  │ JWT Validation + Policy Check  ││
│  │   ↓                            ││
│  │ Allow/Deny Decision            ││
│  └─────────────────────────────────┘│
│              ↓                      │
│  Employee API Application           │
└─────────────────────────────────────┘
```

## Test Data

### Test Users (configured by setup-keycloak.sh)
- **alice.manager** / `password123`
  - Roles: `manager`
  - Employee ID: `MGR001`
  - Department: `Management`
  - Permissions: Full CRUD access

- **bob.employee** / `password123`
  - Roles: `employee`
  - Employee ID: `EMP003`
  - Department: `Engineering`
  - Permissions: Read-only access

### Test Employee (for CRUD operations)
- ID: `EMP999`
- Name: `Test Employee`
- Department: `Engineering`
- Email: `test@company.com`

## Authorization Policies Tested

The tests validate these OPA policies:

1. **Health Endpoint**: Always accessible (no auth required)
2. **Employee Role**: 
   - ✅ GET `/api/v1/employees` (read access)
   - ❌ POST/PUT/DELETE (write operations denied)
3. **Manager Role**:
   - ✅ GET `/api/v1/employees` (read access)
   - ✅ POST/PUT/DELETE (full write access)
4. **No Token**: All API endpoints return 403 Forbidden

## Environment Configuration

### Istio Gateway Access
- **Host**: `opa-demo.local` (via /etc/hosts)
- **URL**: `http://localhost` (via SSH tunnel)
- **Endpoints**:
  - Health: `http://localhost/health`
  - Employee API: `http://localhost/api/v1/employees`
  - Keycloak: `http://localhost/auth`

### Keycloak Configuration
- **Realm**: `employee-management`
- **Client ID**: `employee-api`
- **Client Secret**: Auto-configured by setup script
- **Token Endpoint**: `http://localhost/auth/realms/employee-management/protocol/openid-connect/token`

## Troubleshooting

### SSH Tunnel Issues
```bash
# Check tunnel status
ps aux | grep ssh

# Restart tunnel
./scripts/setup-tunnel.sh

# Check connectivity
curl -H "Host: opa-demo.local" http://localhost/health
```

### Service Not Running
```bash
# Check pod status
kubectl get pods -n opa-keycloak

# Check Istio Gateway
kubectl get gateway -n opa-keycloak
kubectl get virtualservice -n opa-keycloak

# Redeploy if needed
./scripts/helm-deploy-istio.sh
```

### Authentication Issues
```bash
# Check Keycloak realm
curl -s -H "Host: opa-demo.local" \
  "http://localhost/auth/realms/employee-management/.well-known/openid_configuration" | jq .

# Reconfigure Keycloak
./scripts/setup-keycloak.sh
```

### OPA Authorization Issues
```bash
# Check OPA-Envoy logs
kubectl logs -l app=opa-envoy -n opa-keycloak --tail=20

# Check for recent decisions
kubectl logs -l app=opa-envoy -n opa-keycloak --tail=50 | grep decision

# Verify AuthorizationPolicy
kubectl get authorizationpolicy -n opa-keycloak -o yaml
```

### Missing Dependencies
```bash
# Install jq (macOS)
brew install jq

# Install jq (Ubuntu)
sudo apt-get install jq

# Install kubectl
# Follow: https://kubernetes.io/docs/tasks/tools/install-kubectl/
```

## Performance Expectations

The tests measure and validate:
- **Response Time**: < 500ms (excellent), < 1000ms (good)
- **OPA Query Time**: < 1ms (typical: ~0.26ms)
- **Authorization Overhead**: Minimal (< 10ms additional latency)

## Integration with CI/CD

```yaml
# Example GitHub Actions workflow
name: OPA-Keycloak Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Kubernetes
        uses: helm/kind-action@v1
      - name: Deploy Services
        run: ./scripts/helm-deploy-istio.sh
      - name: Setup Keycloak
        run: ./scripts/setup-keycloak.sh
      - name: Run Tests
        run: ./tests/run-all-tests.sh
```

## Manual Testing Examples

After running the tests, you can use the generated tokens for manual testing:

```bash
# Get tokens (from test output)
EMPLOYEE_TOKEN="eyJhbGciOiJSUzI1NiIs..."
MANAGER_TOKEN="eyJhbGciOiJSUzI1NiIs..."

# Test employee access (read-only)
curl -H "Host: opa-demo.local" \
     -H "Authorization: Bearer $EMPLOYEE_TOKEN" \
     "http://localhost/api/v1/employees"

# Test employee denied write
curl -X POST -H "Host: opa-demo.local" \
     -H "Authorization: Bearer $EMPLOYEE_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"id":"TEST","name":"Test"}' \
     "http://localhost/api/v1/employees"
# Returns: 403 Forbidden

# Test manager full access
curl -X POST -H "Host: opa-demo.local" \
     -H "Authorization: Bearer $MANAGER_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"id":"MGR999","name":"New Manager","department":"IT"}' \
     "http://localhost/api/v1/employees"
# Returns: 201 Created
``` 