# OPA + Keycloak Authorization System

A complete example of integrating Open Policy Agent (OPA) with Keycloak for REST API authorization in Kubernetes, deployed using Helm charts.

## Project Structure

```
opa-keycloak/
├── apps/
│   ├── employee-api/          # Employee API application
│   │   ├── app.py            # Python REST API
│   │   ├── app-postgres.py   # PostgreSQL-enabled version
│   │   ├── Dockerfile        # Docker build configuration
│   │   └── requirements.txt  # Python dependencies
│   └── auth-service/         # Authentication service
│       ├── app.py           # JWT validation service
│       ├── Dockerfile       # Docker build configuration
│       └── requirements.txt # Python dependencies
├── helm/
│   └── opa-keycloak-postgres/ # Helm chart for complete deployment
│       ├── Chart.yaml        # Chart metadata
│       ├── values.yaml       # Configuration values
│       └── templates/        # Kubernetes templates
├── k8s/
│   └── system/              # System configuration (Docker compatibility)
├── scripts/                 # Build and deployment scripts
│   ├── helm-deploy-clean.sh # Main deployment script (recommended)
│   ├── build-postgres-images.sh # Build Docker images
│   ├── setup-keycloak.sh    # Keycloak configuration
│   ├── setup-minikube-docker.sh # Docker setup for minikube
│   └── test-*.sh           # Testing scripts
└── docs/
    ├── OPA-Keycloak-Practice-Guide.md # Complete setup guide
    └── HELM-MIGRATION.md     # Migration guide from manifests to Helm
```

## Quick Start

### Prerequisites

- Kubernetes cluster (minikube recommended)
- kubectl configured
- Helm 3.x installed
- Docker access to minikube
- jq installed

### 1. Deploy Complete System

```bash
# Deploy everything with one command
./scripts/helm-deploy-clean.sh

# This script will:
# - Clean up any existing deployments
# - Build Docker images
# - Deploy using Helm chart
# - Verify all services are running
```

### 2. Configure Keycloak

```bash
# Configure Keycloak with users, roles, and client
./scripts/setup-keycloak.sh
```

### 3. Test the System

```bash
# Test CRUD operations
./scripts/test-crud-operations.sh

# Test database operations
./scripts/test-database-setup.sh
```

## Architecture

```
Client Request → Kong Gateway → Employee API → PostgreSQL Database
                       ↓              ↓
                   OPA Service → Auth Service → Keycloak (JWT Validation)
```

## Key Components

- **Employee API**: REST API with PostgreSQL backend
- **Auth Service**: JWT token validation service
- **Keycloak**: Identity and access management
- **OPA**: Policy-based authorization
- **Kong Gateway**: API gateway with rate limiting and routing
- **PostgreSQL**: Database backend

## Authorization Rules

- **Managers**: Full access to all employee records
- **HR Staff**: Can view and update employee records (no delete)
- **Employees**: Can only view their own records
- **Guests**: No access

## Development Workflow

### Full Deployment

```bash
# Clean deployment (recommended for development)
./scripts/helm-deploy-clean.sh

# For cloud minikube
export MINIKUBE_IN_THE_CLOUD=y
export SPOT_INSTANCE_DNS_NAME=your-instance-dns
./scripts/helm-deploy-clean.sh
```

### Building Images Only

```bash
# Build all Docker images
./scripts/build-postgres-images.sh
```

### Configuration

Edit `helm/opa-keycloak-postgres/values.yaml` to customize:
- Image tags and repositories
- Resource limits
- Database configuration
- Service ports

## Cloud Minikube Setup

For cloud deployments, set these environment variables:

```bash
export MINIKUBE_IN_THE_CLOUD=y
export SPOT_INSTANCE_DNS_NAME=your-ec2-instance.compute.amazonaws.com
export MINIKUBE_SSH_KEY=~/.config/cloudkube/minikube-ssh-key
```

## Key Features

- ✅ **Helm-based deployment**: Single command deployment with proper lifecycle management
- ✅ **PostgreSQL backend**: Persistent data storage
- ✅ **JWT token-based authentication**: Secure token validation
- ✅ **Fine-grained authorization**: Policy-based access control with OPA
- ✅ **API Gateway**: Kong gateway with rate limiting and routing
- ✅ **Health checks**: Comprehensive service monitoring
- ✅ **Cloud-ready**: Supports both local and cloud minikube deployments
- ✅ **Clean deployments**: Automatic cleanup and fresh deployments

## Troubleshooting

### Check Service Status
```bash
kubectl get pods -n opa-keycloak
kubectl get services -n opa-keycloak
```

### View Logs
```bash
kubectl logs -l app=employee-api -n opa-keycloak
kubectl logs -l app=keycloak -n opa-keycloak
kubectl logs -l app=opa -n opa-keycloak
```

### Test Individual Services
```bash
# Port forward services for testing
kubectl port-forward service/keycloak-service 8082:8080 -n opa-keycloak &
kubectl port-forward service/employee-api-service 3000:80 -n opa-keycloak &
kubectl port-forward service/opa-service 8181:8181 -n opa-keycloak &
```

### Database Issues
```bash
# Check database connection
./scripts/test-database-clean.sh

# Reset database
kubectl delete pvc postgres-pvc -n opa-keycloak
./scripts/helm-deploy-clean.sh
```

## Migration from Manifests

If you're migrating from the old manifest-based deployment, see `HELM-MIGRATION.md` for detailed instructions.

## Contributing

1. Make changes to application code in `apps/`
2. Update Helm chart in `helm/opa-keycloak-postgres/` if needed
3. Test with `./scripts/helm-deploy-clean.sh`
4. Run tests with `./scripts/test-crud-operations.sh`
5. Commit changes and update documentation 