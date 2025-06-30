# Robust Deployment Guide

This guide documents the improved, robust deployment process for the OPA-Keycloak demo with cloud minikube.

## 🚀 **Quick Start**

For a fresh deployment, run these commands in order:

```bash
# 1. Install Istio
./scripts/install-istio.sh

# 2. Build your microservices
./build-update.sh employee-api latest
./build-update.sh merchant-api  # defaults to 'latest' tag

# 3. Deploy everything
./scripts/helm-deploy-clean.sh

# 4. Setup Keycloak
./scripts/setup-keycloak.sh

# 5. Setup tunnel for access
./scripts/setup-tunnel.sh

# 6. Test the deployment
./tests/run-all-tests.sh
```

## 🔧 **Key Improvements**

### 1. **Fixed Tunnel Configuration**
- **Problem**: Tunnel script was using incorrect ports and SSH configuration
- **Solution**: Updated tunnel script to use correct NodePort (31772) from existing Istio Gateway
- **Benefit**: Reliable tunnel setup using the working Istio Gateway service

### 2. **Robust Helm Deployment**
- **Problem**: Partial failures when resources already exist
- **Solution**: Try install first, fallback to upgrade
- **Benefit**: Handles both fresh and existing deployments

### 3. **Consistent Image Naming**
- **Problem**: Build script vs Helm template image name mismatches
- **Solution**: Unified image naming strategy
- **Benefit**: Images built with `build-update.sh` are always used

### 4. **Improved Tunnel Management**
- **Problem**: Manual tunnel setup, hard to stop
- **Solution**: Automated tunnel with cleanup scripts
- **Benefit**: Easy start/stop, handles conflicts

## 📋 **Environment Variables**

Set these for cloud minikube:

```bash
export MINIKUBE_IN_THE_CLOUD=y
export SPOT_INSTANCE_DNS_NAME=your-minikube-host.com
export MINIKUBE_SSH_KEY=~/.config/cloudkube/minikube-ssh-key
```

## 🛠 **Scripts Overview**

### Core Deployment Scripts
- `build-update.sh` - Build images and update deployments
- `scripts/helm-deploy-clean.sh` - Deploy/upgrade Helm chart
- `scripts/setup-tunnel.sh` - Setup SSH tunnel
- `scripts/stop-tunnel.sh` - Stop SSH tunnel

### Supporting Scripts
- `scripts/install-istio.sh` - Install Istio
- `scripts/setup-keycloak.sh` - Configure Keycloak
- `tests/run-all-tests.sh` - Run all tests

## 🔄 **Development Workflow**

### Making Changes to a Service

1. **Build and deploy**:
   ```bash
   ./build-update.sh merchant-api  # defaults to latest
   # or with specific tag:
   ./build-update.sh merchant-api v1.2.3
   # or build-only mode:
   ./build-update.sh merchant-api --build-only
   ```

2. **Verify deployment**:
   ```bash
   kubectl get pods -n opa-keycloak -l app=merchant-api
   ```

3. **Test changes**:
   ```bash
   ./tests/05-merchant-api.sh
   ```

### Debugging Deployments

1. **Check pod status**:
   ```bash
   kubectl get pods -n opa-keycloak
   ```

2. **Check deployment status**:
   ```bash
   kubectl get deployments -n opa-keycloak
   ```

3. **View logs**:
   ```bash
   kubectl logs -n opa-keycloak -l app=merchant-api --tail=50
   ```

4. **Check Helm status**:
   ```bash
   helm status opa-keycloak -n opa-keycloak
   ```

## 🌐 **Network Access**

### Service Endpoints (via tunnel)
- **Keycloak**: http://opa-demo.local/auth/
- **Employee API**: http://opa-demo.local/api/v1/employees
- **Merchant API**: http://opa-demo.local/api/v1/merchants
- **Health Check**: http://opa-demo.local/health

### Tunnel Management
```bash
# Start tunnel
./scripts/setup-tunnel.sh

# Stop tunnel
./scripts/stop-tunnel.sh

# Check tunnel status
ps aux | grep ssh | grep 30080
```

## 🐛 **Troubleshooting**

### Common Issues

#### 1. **ImagePullBackOff Error**
```bash
# Check if image exists
kubectl get pods -n opa-keycloak -o wide

# Rebuild image
./build-update.sh <service> <tag>
```

#### 2. **Helm Install/Upgrade Failures**
```bash
# Check existing resources
kubectl get all -n opa-keycloak

# Force cleanup if needed
helm uninstall opa-keycloak -n opa-keycloak
kubectl delete namespace opa-keycloak
```

#### 3. **Tunnel Connection Issues**
```bash
# Stop existing tunnels
./scripts/stop-tunnel.sh

# Check port availability
lsof -i :80

# Restart tunnel
./scripts/setup-tunnel.sh
```

#### 4. **Service Not Responding**
```bash
# Check service endpoints
kubectl get endpoints -n opa-keycloak

# Check if pods are ready
kubectl get pods -n opa-keycloak -o wide

# Test internal connectivity
kubectl exec -n opa-keycloak -it deployment/employee-api -- curl http://merchant-api-service:8080/api/v1/merchants/health
```

## 📊 **Monitoring**

### Health Checks
```bash
# All services status
kubectl get pods -n opa-keycloak

# Specific service health
curl http://opa-demo.local/health
curl http://opa-demo.local/api/v1/merchants/health
```

### Resource Usage
```bash
# Pod resource usage
kubectl top pods -n opa-keycloak

# Node resource usage
kubectl top nodes
```

## 🔐 **Security Notes**

- SSH keys are stored in `~/.config/cloudkube/`
- Keycloak admin credentials: `admin/admin123`
- Database passwords are in Helm values
- OPA policies are in `docs/opa-policies/`

## 📝 **Best Practices**

1. **Always use `build-update.sh`** for building images
2. **Test locally first** before cloud deployment
3. **Check logs** after each deployment step
4. **Use fixed tags** for production deployments
5. **Clean up tunnels** when done working

## 🔄 **Cleanup**

### Complete Cleanup
```bash
# Stop tunnel
./scripts/stop-tunnel.sh

# Uninstall Helm chart
helm uninstall opa-keycloak -n opa-keycloak

# Remove namespace
kubectl delete namespace opa-keycloak

# Uninstall Istio (if needed)
./scripts/uninstall-istio.sh
``` 