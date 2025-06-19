# Accessing Services via Istio Service Mesh

This guide explains how to access your OPA-Keycloak services through Istio service mesh using your SSH tunnel setup.

## Prerequisites

1. **SSH Tunnel**: You need to set up an SSH tunnel that forwards both Kubernetes API (port 8443) and Istio Gateway traffic (port 80 -> 31940)
2. **Hosts File**: Your `/etc/hosts` file should have `opa-demo.local` pointing to `127.0.0.1`
3. **Istio**: Istio service mesh is installed and configured

## Setting up the SSH Tunnel

Use the provided script:
```bash
./scripts/setup-tunnel.sh
```

Or manually run:
```bash
sudo ssh -i ~/.ssh/dev-machine.pem \
    -L 8443:192.168.49.2:8443 \
    -L 80:192.168.49.2:31940 \
    ec2-user@$(cloudkube ip)
```

**Note**: Port 80 requires sudo privileges. The tunnel forwards port 80 to Istio Gateway's NodePort 31940.

## Service Access URLs

Once your tunnel is established, you can access services at:

### Keycloak Admin Console
- **URL**: http://opa-demo.local/auth/admin/ (redirects to http://opa-demo.local/auth/admin/master/console/)
- **Username**: admin
- **Password**: admin123

### Keycloak Authentication
- **Base URL**: http://opa-demo.local/auth/
- **Realm**: Configure through admin console

### Employee API
- **Base URL**: http://opa-demo.local/api/v1/employees
- **Health Check**: http://opa-demo.local/health

### OPA Policy Engine
- **Base URL**: http://opa-demo.local/opa/

## Istio Gateway Routes

The following routes are configured in Istio VirtualService:

| Path | Service | Description |
|------|---------|-------------|
| `/auth/*` | Keycloak | Authentication service |
| `/api/v1/employees/*` | Auth Service | Employee API with authentication |
| `/health` | Employee API | Health check endpoint |
| `/opa/*` | OPA | Policy engine (URI rewritten to `/`) |

## Troubleshooting

### Cannot Access Services
1. Verify SSH tunnel is active: `netstat -an | grep :80`
2. Check Istio Gateway status: `kubectl get gateway,virtualservice -n opa-keycloak`
3. Verify pods are running with sidecars: `kubectl get pods -n opa-keycloak` (should show 2/2 ready)
4. Check Istio Gateway: `kubectl get svc -n istio-system istio-ingressgateway`

### DNS Resolution Issues
1. Confirm `/etc/hosts` entry: `ping opa-demo.local`
2. Try accessing via IP: `curl -H "Host: opa-demo.local" http://127.0.0.1/health`

### Port 80 Access Denied
- Port 80 requires root privileges
- Use `sudo` when establishing the SSH tunnel
- Alternative: Use a different port like 8080 and update the tunnel command

## Example API Calls

```bash
# Health check
curl http://opa-demo.local/health

# Access Keycloak admin
open http://opa-demo.local/auth/admin/

# Employee API (requires authentication)
curl http://opa-demo.local/api/v1/employees
``` 