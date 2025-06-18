# OPA-Keycloak Test Suite

This directory contains comprehensive tests for the OPA-Keycloak authorization system using curl-based testing.

## Test Structure

```
tests/
├── README.md                 # This file
├── run-all-tests.sh         # Master test runner
├── 01-basic-connectivity.sh # Service connectivity tests
├── 02-employee-crud.sh      # Employee API CRUD operations
└── 03-authentication.sh     # Keycloak authentication tests
```

## Prerequisites

1. **Services deployed**: Run `./scripts/helm-deploy-clean.sh` first
2. **Required tools**:
   - `kubectl` - Kubernetes CLI
   - `curl` - HTTP client
   - `jq` - JSON processor
   - `bash` - Shell (version 4+ recommended)

## Running Tests

### Run All Tests (Recommended)
```bash
# Run complete test suite
./tests/run-all-tests.sh
```

This script will:
- Check prerequisites
- Set up port forwarding automatically
- Run all tests in sequence
- Clean up port forwards on exit
- Provide a summary report

### Run Individual Tests

First, set up port forwarding manually:
```bash
# Terminal 1: Employee API
kubectl port-forward service/employee-api-service 3000:8080 -n opa-keycloak

# Terminal 2: Keycloak
kubectl port-forward service/keycloak-service 8082:8080 -n opa-keycloak

# Terminal 3: Auth Service (optional)
kubectl port-forward service/auth-service 8081:80 -n opa-keycloak
```

Then run individual tests:
```bash
# Test service connectivity
./tests/01-basic-connectivity.sh

# Test CRUD operations
./tests/02-employee-crud.sh

# Test authentication (requires Keycloak setup)
./tests/03-authentication.sh
```

## Test Details

### 1. Basic Connectivity Test (`01-basic-connectivity.sh`)
- ✅ Employee API health check
- ✅ Keycloak health check
- ✅ Auth Service accessibility
- ✅ Employee data availability
- ✅ Keycloak realm configuration

**Expected Output:**
```
🔗 Basic Connectivity Test
==========================
[INFO] Testing service connectivity...
[SUCCESS] ✅ Employee API is healthy
[SUCCESS] ✅ Keycloak is healthy
[SUCCESS] ✅ Employee data is available
```

### 2. Employee CRUD Test (`02-employee-crud.sh`)
- ✅ CREATE: Add new employee
- ✅ READ: Get all employees, specific employee, departments
- ✅ UPDATE: Modify employee data
- ✅ DELETE: Remove employee
- ✅ FILTER: Department-based filtering

**Expected Output:**
```
👥 Employee CRUD Operations Test
================================
[SUCCESS] ✅ CREATE: Employee created successfully
[SUCCESS] ✅ READ ALL: Found 7 employees
[SUCCESS] ✅ UPDATE: Employee updated successfully
[SUCCESS] ✅ DELETE: Employee deleted successfully
```

### 3. Authentication Test (`03-authentication.sh`)
- ✅ Keycloak realm configuration
- ✅ User authentication with JWT tokens
- ✅ Token validation via Auth Service
- ✅ Token refresh functionality
- ✅ JWT payload decoding

**Setup Required:**
```bash
# Configure Keycloak first
./scripts/setup-keycloak.sh

# Set client secret (obtained from Keycloak admin)
export CLIENT_SECRET='your-client-secret'
```

**Expected Output:**
```
🔐 Authentication Test
======================
[SUCCESS] ✅ Realm 'employee-management' is configured
[SUCCESS] ✅ Authentication successful for alice.manager
[SUCCESS] ✅ Token validation successful
```

## Environment Variables

### Required for Authentication Tests
- `CLIENT_SECRET`: Keycloak client secret (get from admin console)

### Optional
- `EMPLOYEE_API_URL`: Default `http://localhost:3000`
- `KEYCLOAK_URL`: Default `http://localhost:8082`
- `AUTH_SERVICE_URL`: Default `http://localhost:8081`

## Test Data

The tests use the following test data:

### Test Employee (for CRUD operations)
- ID: `EMP999`
- Name: `Test Employee`
- Department: `Engineering`
- Email: `test@company.com`

### Test Users (for authentication)
- `alice.manager` / `password123` - Manager role
- `bob.employee` / `password123` - Employee role
- `jane.hr` / `password123` - HR role

## Troubleshooting

### Port Forward Issues
```bash
# Kill existing port forwards
pkill -f "kubectl port-forward"

# Check if ports are in use
lsof -i :3000 -i :8082 -i :8081

# Restart port forwards
./tests/run-all-tests.sh
```

### Service Not Running
```bash
# Check pod status
kubectl get pods -n opa-keycloak

# Redeploy if needed
./scripts/helm-deploy-clean.sh
```

### Authentication Issues
```bash
# Check if Keycloak is configured
curl -s http://localhost:8082/realms/employee-management/.well-known/openid_configuration

# Configure Keycloak
./scripts/setup-keycloak.sh

# Get client secret from Keycloak admin console
echo "Visit: http://localhost:8082/admin"
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

## Integration with CI/CD

The test suite is designed to be CI/CD friendly:

```bash
# Return codes
# 0 = All tests passed
# 1 = Some tests failed

# Example usage in CI
./tests/run-all-tests.sh && echo "Deploy to production" || echo "Tests failed"
```

## Test Output Files

Tests may create temporary files:
- `/tmp/test-tokens.env` - JWT tokens for cross-test usage

These are automatically cleaned up or can be used for debugging.

## Contributing

When adding new tests:

1. Follow the naming convention: `##-test-name.sh`
2. Use the standard color functions and output format
3. Include proper error handling and cleanup
4. Update the `TESTS` array in `run-all-tests.sh`
5. Add documentation to this README 