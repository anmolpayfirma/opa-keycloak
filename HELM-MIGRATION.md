# Helm Migration Guide

This document explains the migration from loose Kubernetes manifests to a clean Helm-based deployment approach, inspired by proven production patterns.

## 🚀 Why Helm?

Based on the HQ project's successful deployment patterns, we've migrated to a Helm-only approach that provides:

- **Clean Lifecycle Management**: Complete install/uninstall/upgrade cycles
- **Consistent Deployments**: Templated configurations with environment-specific values
- **Dependency Management**: Proper handling of service dependencies
- **Rollback Capabilities**: Easy rollback to previous versions
- **Secret Management**: Centralized secret handling
- **No Manifest Drift**: Single source of truth for all configurations

## 📁 New Structure

```
helm/
└── opa-keycloak-postgres/          # Main Helm chart
    ├── Chart.yaml                  # Chart metadata
    ├── values.yaml                 # Default configuration values
    └── templates/                  # Kubernetes resource templates
        ├── auth-service.yaml
        ├── employee-api.yaml
        ├── keycloak.yaml
        ├── kong.yaml
        ├── opa.yaml
        ├── postgresql.yaml
        └── ingress.yaml

scripts/
├── helm-deploy-clean.sh           # Main deployment script (HQ pattern)
├── cleanup-manifests.sh           # Legacy cleanup script
└── [legacy scripts...]            # Old scripts (can be removed)
```

## 🔄 Migration Steps

### 1. Clean Up Legacy Deployments

First, clean up any existing deployments from loose manifests:

```bash
# Clean up legacy resources
./scripts/cleanup-manifests.sh

# Or manually delete namespace
kubectl delete namespace opa-keycloak-practice
```

### 2. Deploy with Helm

Use the new clean deployment script:

```bash
# Deploy everything with Helm
./scripts/helm-deploy-clean.sh
```

This script follows the HQ pattern and handles:
- ✅ Secret cleanup and recreation
- ✅ Helm release uninstall/reinstall
- ✅ Docker image cleanup and rebuild
- ✅ Dependency updates
- ✅ Complete deployment verification
- ✅ Health checks and connectivity tests

### 3. Verify Deployment

The script automatically verifies:
- All pods are running
- Database connectivity
- API health checks
- Service accessibility

## 🛠️ Key Features

### Inspired by HQ Production Patterns

The new deployment script (`helm-deploy-clean.sh`) implements proven patterns:

```bash
# 1. Clean secret management
kubectl -n${NAMESPACE} delete secrets $(kubectl -n${NAMESPACE} get secrets -o jsonpath='{...}')

# 2. Proper release lifecycle
helm -n${NAMESPACE} uninstall ${RELEASE_NAME} --wait

# 3. Image cleanup for fresh pulls
docker images | grep ${REGISTRY} | grep latest | xargs -r docker rmi -f

# 4. Dependency management
helm dependency update

# 5. Robust installation with timeouts
helm install ${RELEASE_NAME} ${CHART_PATH} --wait --timeout 10m
```

### Environment Support

- **Local Minikube**: Automatic detection and docker-env setup
- **Cloud Minikube**: SSH-based Docker builds with proper key management
- **Multi-Environment**: Easy values override for different environments

### Configuration Management

All configuration is centralized in `helm/opa-keycloak-postgres/values.yaml`:

```yaml
global:
  namespace: opa-keycloak
  registry: localhost:5000
  domain: opa-demo.local

postgresql:
  enabled: true
  persistence:
    enabled: true
    size: 5Gi

employeeApi:
  image: localhost:5000/employee-api:latest
  replicas: 1
```

## 🎯 Benefits Achieved

### 1. **No More Manifest Drift**
- Single source of truth in Helm charts
- Templated configurations prevent inconsistencies
- Version-controlled releases

### 2. **Clean Deployments**
- Complete cleanup before each deployment
- Fresh image pulls ensure latest code
- Proper dependency ordering

### 3. **Production Ready**
- Robust error handling and validation
- Comprehensive health checks
- Proper resource cleanup

### 4. **Simplified Operations**
```bash
# Deploy everything
./scripts/helm-deploy-clean.sh

# Check status
helm list -n opa-keycloak

# View logs
kubectl logs -f deployment/employee-api -n opa-keycloak

# Rollback if needed
helm rollback opa-keycloak -n opa-keycloak
```

## 🗑️ Legacy Cleanup

After successful migration, you can remove:

```bash
# Legacy manifest files (already moved to Helm templates)
rm -rf k8s/manifests/

# Legacy scripts (replace with helm-deploy-clean.sh)
rm scripts/deploy.sh
rm scripts/build-and-deploy.sh
rm scripts/deploy-postgres.sh
```

## 🔧 Troubleshooting

### Common Issues

1. **Image Pull Issues**
   - Ensure minikube docker-env is set
   - Check registry accessibility
   - Verify image tags in values.yaml

2. **Namespace Issues**
   - The script creates the namespace automatically
   - Default namespace is now `opa-keycloak`

3. **Resource Conflicts**
   - Run cleanup script first
   - Check for stuck resources: `kubectl get all -A`

### Debug Commands

```bash
# Check Helm status
helm status opa-keycloak -n opa-keycloak

# View all resources
kubectl get all -n opa-keycloak

# Check pod logs
kubectl logs -f deployment/employee-api -n opa-keycloak

# Describe problematic resources
kubectl describe pod <pod-name> -n opa-keycloak
```

## 🎉 Success!

You now have a production-ready, Helm-based deployment that:
- ✅ Follows proven HQ patterns
- ✅ Provides clean lifecycle management
- ✅ Supports both local and cloud environments
- ✅ Includes comprehensive verification
- ✅ Eliminates manifest drift
- ✅ Enables easy rollbacks and upgrades 