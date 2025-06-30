# OPA + Keycloak Helm Chart

A comprehensive Helm chart for deploying a production-ready OPA + Keycloak authorization system with PostgreSQL database backend.

## 🚀 Features

- **PostgreSQL 15** with persistent storage
- **Keycloak** with database persistence 
- **Employee API** with full CRUD operations
- **OPA Policy Engine** for authorization
- **Auth Service** for JWT validation
- **Istio Gateway** for API management
- **NGINX Ingress** for external access
- **Configurable** through Helm values
- **Production ready** with security contexts and resource limits

## 📋 Prerequisites

- Kubernetes cluster (minikube, EKS, GKE, etc.)
- Helm 3.x installed
- kubectl configured
- Docker images built (see [Building Images](#building-images))

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Istio Gateway   │───▶│   OPA-Envoy      │───▶│       OPA       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │
         ▼                        ▼
┌─────────────────┐    ┌──────────────────┐
│  Employee API   │───▶│   PostgreSQL     │
│  (PostgreSQL)   │    │   Database       │
└─────────────────┘    └──────────────────┘
```

## 📦 Installation

### Quick Start

1. **Build Docker Images** (if not already built):
   ```bash
   ./scripts/build-images.sh
   ```

2. **Deploy with Helm**:
   ```bash
   ./scripts/helm-deploy-clean.sh
   ```

### Manual Installation

1. **Validate the chart**:
   ```bash
   helm lint helm/opa-keycloak
   ```

2. **Install the chart**:
   ```bash
   helm install opa-keycloak helm/opa-keycloak \
     --namespace default \
     --create-namespace \
     --wait \
     --timeout 10m
   ```

3. **Check the deployment**:
   ```bash
   kubectl get pods
   kubectl get services
   kubectl get pvc
   ```

## 🔧 Configuration

### Values.yaml Overview

The chart is highly configurable through the `values.yaml` file:

```yaml
global:
  cloudMinikube: true              # Set to true for cloud minikube
  domain: opa-demo.local          # Domain for ingress
  namespace: default              # Target namespace

postgresql:
  enabled: true                   # Enable PostgreSQL
  persistence:
    enabled: true
    size: 5Gi                    # Storage size
  resources:                     # Resource limits
    requests:
      memory: "256Mi"
      cpu: "100m"

keycloak:
  enabled: true                   # Enable Keycloak
  replicas: 1                    # Number of replicas
  admin:
    username: admin              # Admin username
    password: admin123           # Admin password

employeeApi:
  enabled: true                   # Enable Employee API
  image: localhost:5000/employee-api:v2.0.0
  replicas: 1

# ... more configuration options
```

### Key Configuration Options

| Component | Setting | Default | Description |
|-----------|---------|---------|-------------|
| PostgreSQL | `postgresql.persistence.size` | `5Gi` | Database storage size |
| Keycloak | `keycloak.admin.password` | `admin123` | Admin password |
| Employee API | `employeeApi.image` | `localhost:5000/employee-api:latest` | Docker image |
| Istio | `istio.enabled` | `true` | Enable Istio Gateway |
| Ingress | `ingress.enabled` | `true` | Enable NGINX Ingress |

## 🐳 Building Images

### Using the Build Script

```bash
# Build all required images
./scripts/build-images.sh
```

### Manual Build

```bash
# Set up minikube Docker environment
eval $(minikube docker-env)

# Build Employee API
cd apps/employee-api
docker build -t localhost:5000/employee-api:v2.0.0 .
# Use the build script instead
./build-update.sh employee-api latest --build-only
./build-update.sh merchant-api latest --build-only
```

## 🧪 Testing

### Database Setup Test
```bash
./scripts/test-database-setup.sh
```

### CRUD Operations Test
```bash
./scripts/test-crud-operations.sh
```

### Manual Testing
```bash
# Check all pods are running
kubectl get pods

# Test database connectivity
kubectl run db-test --image=postgres:15-alpine --rm -i --restart=Never -- \
  psql -h postgresql-service -U postgres -d opa_demo -c "SELECT 1;"

# Test Employee API health
kubectl exec $(kubectl get pod -l app=employee-api -o jsonpath='{.items[0].metadata.name}') -- \
  curl -s http://localhost:8080/health
```

## 🔗 Access

### Local Minikube
```bash
# Add to /etc/hosts
echo "$(minikube ip) opa-demo.local" >> /etc/hosts

# Access URLs
open http://opa-demo.local/api/v1/employees
open http://opa-demo.local/keycloak/admin
```

### Cloud Minikube
```bash
# Add to /etc/hosts
echo "192.168.49.2 opa-demo.local" >> /etc/hosts

# Access through SSH tunnel
# URLs work the same as local minikube
```

## 📊 Management

### Helm Commands

```bash
# Check release status
helm status opa-keycloak

# Upgrade release
helm upgrade opa-keycloak helm/opa-keycloak

# Uninstall release
helm uninstall opa-keycloak

# View release history
helm history opa-keycloak

# Get all resources
kubectl get all -l app.kubernetes.io/instance=opa-keycloak
```

### Database Management

```bash
# Connect to PostgreSQL
kubectl run -i --tty --rm debug --image=postgres:15-alpine --restart=Never -- \
  psql -h postgresql-service -U postgres -d opa_demo

# Check database sizes
kubectl run db-size-check --image=postgres:15-alpine --rm -i --restart=Never -- \
  psql -h postgresql-service -U postgres -d opa_demo -c \
  "SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database WHERE datistemplate = false;"

# Backup database
kubectl exec -i $(kubectl get pod -l app=postgresql -o jsonpath='{.items[0].metadata.name}') -- \
  pg_dump -U postgres employee_api > backup-$(date +%Y%m%d).sql
```

## 🔐 Security

### Database Security
- Separate database users for each service
- Encrypted passwords stored in Kubernetes secrets
- Network isolation within cluster
- Parameterized queries prevent SQL injection

### Container Security
- Non-root container execution
- Security contexts applied
- Resource limits prevent resource exhaustion
- Health checks for monitoring

## 📈 Scaling

### Horizontal Scaling
```bash
# Scale Employee API
helm upgrade opa-keycloak helm/opa-keycloak \
  --set employeeApi.replicas=3

# Scale Keycloak
helm upgrade opa-keycloak helm/opa-keycloak \
  --set keycloak.replicas=2
```

### Resource Scaling
```bash
# Increase PostgreSQL resources
helm upgrade opa-keycloak helm/opa-keycloak \
  --set postgresql.resources.limits.memory=1Gi \
  --set postgresql.persistence.size=10Gi
```

## 🔍 Troubleshooting

### Common Issues

#### Pods Not Starting
```bash
# Check pod status
kubectl get pods
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>
```

#### Image Pull Errors
```bash
# Verify images exist
docker images | grep -E "(employee-api|auth-service)"

# Rebuild images if needed
./scripts/build-images.sh
```

#### Database Connection Issues
```bash
# Check PostgreSQL pod
kubectl get pod -l app=postgresql
kubectl logs -l app=postgresql

# Test connectivity
kubectl run db-test --image=postgres:15-alpine --rm -i --restart=Never -- \
  psql -h postgresql-service -U postgres -d opa_demo -c "SELECT 1;"
```

#### Persistent Volume Issues
```bash
# Check PVC status
kubectl get pvc

# Check storage class
kubectl get storageclass
```

### Getting Help

1. **Check Helm status**: `helm status opa-keycloak`
2. **View all resources**: `kubectl get all -l app.kubernetes.io/instance=opa-keycloak`
3. **Check events**: `kubectl get events --sort-by=.metadata.creationTimestamp`
4. **View logs**: `kubectl logs -l app=<component-name>`

## 🚀 Production Considerations

### High Availability
- Use multiple replicas for stateless services
- Configure PostgreSQL with replication
- Use persistent volumes with appropriate storage class
- Set up proper backup strategies

### Monitoring
- Enable Prometheus metrics
- Set up Grafana dashboards
- Configure alerting for critical issues
- Monitor resource usage and performance

### Security
- Regular security updates for base images
- Database credential rotation
- Network policies for pod-to-pod communication
- RBAC for Kubernetes access control

## 📚 Additional Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [OPA Documentation](https://www.openpolicyagent.org/docs/)
- [Kong Gateway Documentation](https://docs.konghq.com/)
- [Helm Documentation](https://helm.sh/docs/)

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `helm lint` and `helm template`
5. Submit a pull request

## 📄 License

This project is licensed under the Apache 2.0 License - see the LICENSE file for details. 