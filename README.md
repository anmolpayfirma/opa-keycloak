# OPA + Keycloak Authorization System

A complete example of integrating Open Policy Agent (OPA) with Keycloak for REST API authorization in Kubernetes.

## Project Structure

```
opa-keycloak/
├── apps/
│   └── employee-api/          # Employee API application
│       ├── app.py            # Python REST API
│       ├── Dockerfile        # Docker build configuration
│       ├── requirements.txt  # Python dependencies
│       └── README.md         # API documentation
├── k8s/
│   └── manifests/            # Kubernetes manifests
│       ├── employee-api.yaml # Employee API deployment
│       ├── keycloak-deployment.yaml # Keycloak setup
│       └── opa-policies.yaml # OPA policies and deployment
├── scripts/                  # Build and deployment scripts
│   ├── build.sh             # Build Docker image only
│   ├── deploy.sh            # Deploy to Kubernetes only
│   └── build-and-deploy.sh  # Build and deploy together
└── docs/
    └── OPA-Keycloak-Practice-Guide.md # Complete setup guide
```

## Quick Start

### Prerequisites

- Kubernetes cluster (minikube)
- kubectl configured
- Docker access to minikube
- jq installed

### 1. Setup Infrastructure

```bash
# Create namespace
kubectl create namespace opa-keycloak-practice
kubectl config set-context --current --namespace=opa-keycloak-practice

# Deploy Keycloak and OPA
kubectl apply -f k8s/manifests/keycloak-deployment.yaml
kubectl apply -f k8s/manifests/opa-policies.yaml

# Wait for services to be ready
kubectl wait --for=condition=ready pod -l app=keycloak --timeout=300s
kubectl wait --for=condition=ready pod -l app=opa --timeout=300s
```

### 2. Configure Keycloak

Follow the detailed guide in `docs/OPA-Keycloak-Practice-Guide.md` to:
- Create the `employee-management` realm
- Configure users, roles, and client
- Set up protocol mappers for JWT attributes

### 3. Build and Deploy Employee API

```bash
# For cloud minikube setup
export MINIKUBE_IN_THE_CLOUD=y
export SPOT_INSTANCE_DNS_NAME=your-instance-dns

# Build and deploy
./scripts/build-and-deploy.sh

# Or separately
./scripts/build.sh
./scripts/deploy.sh
```

### 4. Test the System

```bash
# Port forward services
kubectl port-forward service/keycloak-service 8082:8080 &
kubectl port-forward service/employee-api-service 3000:80 &

# Get tokens (replace client secret)
export CLIENT_SECRET="your-client-secret"

EMPLOYEE_TOKEN=$(curl -s -X POST \
  http://localhost:8082/realms/employee-management/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=employee-api&client_secret=$CLIENT_SECRET&username=bob.employee&password=password123" \
  | jq -r '.access_token')

# Test authorization
curl -H "Authorization: Bearer $EMPLOYEE_TOKEN" http://localhost:3000/employees/EMP003  # Should work
curl -H "Authorization: Bearer $EMPLOYEE_TOKEN" http://localhost:3000/employees/EMP001  # Should fail
```

## Authorization Rules

- **Managers**: Full access to all employee records
- **HR Staff**: Can view and update employee records (no delete)
- **Employees**: Can only view their own records
- **Guests**: No access

## Development Workflow

### Building Images

```bash
# Build latest version
./scripts/build.sh

# Build specific version
./scripts/build.sh v1.2.3
```

### Deploying

```bash
# Deploy latest
./scripts/deploy.sh

# Deploy specific version
./scripts/deploy.sh v1.2.3
```

### Local Development

```bash
# Run the API locally
cd apps/employee-api
pip install -r requirements.txt
python app.py
```

## Cloud Minikube Setup

The build scripts support cloud minikube deployments. Set these environment variables:

```bash
export MINIKUBE_IN_THE_CLOUD=y
export SPOT_INSTANCE_DNS_NAME=your-ec2-instance.compute.amazonaws.com
export MINIKUBE_SSH_KEY=~/.config/cloudkube/minikube-ssh-key
```

## Architecture

```
Client Request → Employee API → OPA Service → Policy Decision
                       ↓
                Keycloak Token Validation (JWT with custom attributes)
```

## Key Features

- ✅ JWT token-based authentication
- ✅ Fine-grained authorization with OPA
- ✅ Custom user attributes in JWT tokens
- ✅ Proper Docker containerization
- ✅ Kubernetes-native deployment
- ✅ Health checks and monitoring
- ✅ Security best practices (non-root containers)

## Troubleshooting

### Check Service Status
```bash
kubectl get pods -n opa-keycloak-practice
kubectl logs -l app=employee-api -n opa-keycloak-practice
```

### Test OPA Directly
```bash
kubectl port-forward service/opa-service 8181:8181 &
curl -X POST http://localhost:8181/v1/data/system/authz/allow \
  -H "Content-Type: application/json" \
  -d '{"input": {"method": "GET", "path": "/employees/EMP001", "token": "your-jwt-token"}}'
```

### Verify Keycloak Configuration
- Ensure protocol mappers are configured for `employee_id` and `department`
- Check that users have the correct attributes and roles
- Verify client secret matches the one used in API calls

## Contributing

1. Make changes to the application code in `apps/employee-api/`
2. Update Kubernetes manifests in `k8s/manifests/` if needed
3. Test locally with `python apps/employee-api/app.py`
4. Build and deploy with `./scripts/build-and-deploy.sh`
5. Commit changes and update documentation 