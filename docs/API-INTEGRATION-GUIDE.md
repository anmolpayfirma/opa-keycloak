# API Integration Guide
## Adding New Microservices to Istio + OPA + Keycloak Setup

This guide provides a standardized approach to integrate new APIs and microservices into our centralized authentication and authorization infrastructure. Developers can focus on business logic while security is handled by the infrastructure layer.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Istio Service Mesh                          │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │ Employee API│  │ Merchant API│  │  User API   │  + More... │
│  │             │  │             │  │             │            │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │            │
│  │ │Sidecar  │ │  │ │Sidecar  │ │  │ │Sidecar  │ │            │
│  │ │+ OPA    │ │  │ │+ OPA    │ │  │ │+ OPA    │ │            │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Istio Gateway + VirtualService            │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│              Centralized Security Layer                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │  Keycloak   │  │     OPA     │  │    Istio    │            │
│  │ (AuthN)     │  │  (AuthZ)    │  │ (Gateway)   │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start Checklist

For each new API/microservice, follow this checklist:

- [ ] 1. **Create API Application** (any language/framework)
- [ ] 2. **Add Helm Chart Configuration**
- [ ] 3. **Configure Istio Routing**
- [ ] 4. **Define OPA Authorization Policies**
- [ ] 5. **Update Keycloak Roles** (if needed)
- [ ] 6. **Add Integration Tests**
- [ ] 7. **Deploy and Validate**

## 📋 Step-by-Step Integration Process

### Step 1: Create Your API Application

Your API can be built in **any language** (Python, Go, Node.js, Java, etc.). The only requirements:

#### Required Endpoints:
```
GET  /health           # Health check (no auth required)
GET  /api/v1/{resource} # Resource listing
POST /api/v1/{resource} # Resource creation
PUT  /api/v1/{resource}/{id} # Resource update
DELETE /api/v1/{resource}/{id} # Resource deletion
```

#### No Authentication Code Needed:
- ❌ No JWT validation in your code
- ❌ No authorization logic in your code  
- ❌ No CORS handling needed
- ✅ Just focus on business logic!

#### Example Minimal API (Python/Flask):
```python
from flask import Flask, jsonify, request

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

@app.route('/api/v1/merchants', methods=['GET'])
def get_merchants():
    # Business logic only - auth handled by Istio!
    return jsonify({"merchants": []})

@app.route('/api/v1/merchants', methods=['POST'])
def create_merchant():
    # Business logic only - auth handled by Istio!
    data = request.get_json()
    return jsonify({"merchant": data}), 201

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

### Step 2: Add Helm Chart Configuration

#### 2.1 Update `values.yaml`:
```yaml
# Add your new API configuration
merchantApi:
  enabled: true
  image:
    repository: merchant-api
    tag: latest
  service:
    port: 8080
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"

# Update Istio configuration
istio:
  enabled: true
  routes:
    merchantApi:
      enabled: true
      prefix: "/api/v1/merchants"
      service: "merchant-api-service"
      port: 8080
```

#### 2.2 Create Service Template (`templates/merchant-api.yaml`):
```yaml
{{- if .Values.merchantApi.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: merchant-api
  namespace: {{ .Values.global.namespace }}
  labels:
    app: merchant-api
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: merchant-api
      version: v1
  template:
    metadata:
      labels:
        app: merchant-api
        version: v1
    spec:
      containers:
      - name: merchant-api
        image: "{{ .Values.merchantApi.image.repository }}:{{ .Values.merchantApi.image.tag }}"
        ports:
        - containerPort: {{ .Values.merchantApi.service.port }}
        resources:
          {{- toYaml .Values.merchantApi.resources | nindent 10 }}
        livenessProbe:
          httpGet:
            path: /health
            port: {{ .Values.merchantApi.service.port }}
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: {{ .Values.merchantApi.service.port }}
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: merchant-api-service
  namespace: {{ .Values.global.namespace }}
  labels:
    app: merchant-api
spec:
  selector:
    app: merchant-api
  ports:
  - port: {{ .Values.merchantApi.service.port }}
    targetPort: {{ .Values.merchantApi.service.port }}
    name: http
{{- end }}
```

### Step 3: Configure Istio Routing

#### 3.1 Update `istio-gateway.yaml`:
```yaml
# Add new route to VirtualService
http:
# Existing routes...
- match:
  - uri:
      prefix: /api/v1/merchants
  route:
  - destination:
      host: merchant-api-service
      port:
        number: 8080

# Health check for new API
- match:
  - uri:
      exact: /merchant-health
  rewrite:
    uri: /health
  route:
  - destination:
      host: merchant-api-service
      port:
        number: 8080
```

### Step 4: Define OPA Authorization Policies

#### 4.1 Update OPA Policy (`opa-policy.rego`):
```rego
package istio.authz

import rego.v1

# Existing policies...

# Merchant API Authorization
allow if {
    is_merchant_api_request
    is_authenticated
    has_merchant_permission
}

is_merchant_api_request if {
    startswith(input.attributes.request.http.path, "/api/v1/merchants")
}

has_merchant_permission if {
    # Read access for employees and managers
    input.attributes.request.http.method == "GET"
    user_has_role(["employee", "manager", "merchant"])
}

has_merchant_permission if {
    # Write access for managers and merchant admins
    input.attributes.request.http.method in ["POST", "PUT", "DELETE"]
    user_has_role(["manager", "merchant-admin"])
}

# Helper function to check user roles
user_has_role(required_roles) if {
    some role in required_roles
    role in token_payload.realm_access.roles
}
```

#### 4.2 Policy Testing Examples:
```json
// Manager accessing merchants (should allow)
{
  "input": {
    "attributes": {
      "request": {
        "http": {
          "method": "GET",
          "path": "/api/v1/merchants",
          "headers": {
            "authorization": "Bearer <manager-token>"
          }
        }
      }
    }
  }
}

// Employee creating merchant (should deny)
{
  "input": {
    "attributes": {
      "request": {
        "http": {
          "method": "POST",
          "path": "/api/v1/merchants",
          "headers": {
            "authorization": "Bearer <employee-token>"
          }
        }
      }
    }
  }
}
```

### Step 5: Update Keycloak Roles (if needed)

#### 5.1 Add New Roles:
```bash
# Add merchant-specific roles
./scripts/setup-keycloak.sh --add-roles merchant,merchant-admin

# Or manually in Keycloak Admin Console:
# 1. Go to Realm Settings > Roles
# 2. Add roles: merchant, merchant-admin
# 3. Assign to users as needed
```

#### 5.2 Create Test Users:
```bash
# Add test users for new API
./scripts/setup-keycloak.sh --add-user merchant.user merchant-role
./scripts/setup-keycloak.sh --add-user merchant.admin merchant-admin-role
```

### Step 6: Add Integration Tests

#### 6.1 Create API-Specific Test (`tests/04-merchant-api.sh`):
```bash
#!/bin/bash

# Merchant API Test
echo "🏪 Merchant API Test (via Istio Gateway)"
echo "========================================"

# Test unauthorized access
test_endpoint "Merchant API without auth" "403" "-H 'Host: opa-demo.local' '$BASE_URL/api/v1/merchants'"

# Test employee access (read-only)
if [ -n "$EMPLOYEE_TOKEN" ]; then
    test_endpoint "Employee GET merchants" "200" "-H 'Host: opa-demo.local' -H 'Authorization: Bearer $EMPLOYEE_TOKEN' '$BASE_URL/api/v1/merchants'"
    test_endpoint "Employee POST merchant (denied)" "403" "-X POST -H 'Host: opa-demo.local' -H 'Authorization: Bearer $EMPLOYEE_TOKEN' -H 'Content-Type: application/json' -d '{\"name\":\"Test Merchant\"}' '$BASE_URL/api/v1/merchants'"
fi

# Test manager access (full)
if [ -n "$MANAGER_TOKEN" ]; then
    test_endpoint "Manager GET merchants" "200" "-H 'Host: opa-demo.local' -H 'Authorization: Bearer $MANAGER_TOKEN' '$BASE_URL/api/v1/merchants'"
    test_endpoint "Manager POST merchant" "201" "-X POST -H 'Host: opa-demo.local' -H 'Authorization: Bearer $MANAGER_TOKEN' -H 'Content-Type: application/json' -d '{\"name\":\"Test Merchant\"}' '$BASE_URL/api/v1/merchants'"
fi
```

#### 6.2 Update Main Test Runner:
```bash
# Add to tests/run-all-tests.sh
TESTS=(
    "01-basic-connectivity.sh"
    "02-employee-crud.sh"
    "03-authentication.sh"
    "04-merchant-api.sh"  # New test
)
```

### Step 7: Deploy and Validate

#### 7.1 Build and Deploy:
```bash
# Build your API image
docker build -t merchant-api:latest .

# Deploy with Helm
helm upgrade opa-keycloak helm/opa-keycloak --namespace opa-keycloak

# Run tests
./tests/run-all-tests.sh
```

#### 7.2 Validation Checklist:
- [ ] Health endpoint accessible: `curl -H "Host: opa-demo.local" http://localhost/merchant-health`
- [ ] Unauthorized access denied: `curl -H "Host: opa-demo.local" http://localhost/api/v1/merchants` → 403
- [ ] Authorized access works: `curl -H "Host: opa-demo.local" -H "Authorization: Bearer <token>" http://localhost/api/v1/merchants` → 200
- [ ] OPA decisions logged: `kubectl logs -l app=opa-envoy -n opa-keycloak | grep decision`

## 🎯 API-Specific Templates

### Template 1: CRUD API (like Employee API)
```yaml
# Use for: User API, Product API, Order API
permissions:
  read: ["employee", "manager", "admin"]
  write: ["manager", "admin"]
  delete: ["admin"]
```

### Template 2: Admin API
```yaml
# Use for: System API, Config API, Analytics API
permissions:
  read: ["admin"]
  write: ["admin"]
  delete: ["admin"]
```

### Template 3: Public API
```yaml
# Use for: Catalog API, Status API, Documentation API
permissions:
  read: ["public"]  # No auth required
  write: ["admin"]
  delete: ["admin"]
```

### Template 4: Tenant-Specific API
```yaml
# Use for: Merchant API, Organization API, Team API
permissions:
  read: ["employee", "manager", "tenant-user"]
  write: ["manager", "tenant-admin"]
  delete: ["tenant-admin"]
```

## 🔧 Advanced Configuration

### Multi-Tenant Support
```rego
# OPA policy for tenant isolation
allow if {
    is_tenant_api_request
    is_authenticated
    user_tenant == resource_tenant
}

user_tenant := token_payload.tenant_id
resource_tenant := split(input.attributes.request.http.path, "/")[3]
```

### Rate Limiting
```yaml
# Istio EnvoyFilter for rate limiting
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: merchant-api-rate-limit
spec:
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: SIDECAR_INBOUND
      listener:
        filterChain:
          filter:
            name: "envoy.filters.network.http_connection_manager"
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.local_ratelimit
        typed_config:
          "@type": type.googleapis.com/udpa.type.v1.TypedStruct
          type_url: type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
          value:
            stat_prefix: merchant_api_rate_limiter
            token_bucket:
              max_tokens: 100
              tokens_per_fill: 100
              fill_interval: 60s
```

### Observability
```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: merchant-api-metrics
spec:
  selector:
    matchLabels:
      app: merchant-api
  endpoints:
  - port: http
    path: /metrics
```

## 📚 Language-Specific Examples

### Go (Gin)
```go
package main

import (
    "github.com/gin-gonic/gin"
    "net/http"
)

func main() {
    r := gin.Default()
    
    r.GET("/health", func(c *gin.Context) {
        c.JSON(http.StatusOK, gin.H{"status": "healthy"})
    })
    
    r.GET("/api/v1/merchants", func(c *gin.Context) {
        // Business logic only - auth handled by Istio!
        c.JSON(http.StatusOK, gin.H{"merchants": []string{}})
    })
    
    r.Run(":8080")
}
```

### Node.js (Express)
```javascript
const express = require('express');
const app = express();

app.use(express.json());

app.get('/health', (req, res) => {
    res.json({ status: 'healthy' });
});

app.get('/api/v1/merchants', (req, res) => {
    // Business logic only - auth handled by Istio!
    res.json({ merchants: [] });
});

app.listen(8080, '0.0.0.0', () => {
    console.log('Merchant API listening on port 8080');
});
```

### Java (Spring Boot)
```java
@RestController
public class MerchantController {
    
    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "healthy");
    }
    
    @GetMapping("/api/v1/merchants")
    public Map<String, Object> getMerchants() {
        // Business logic only - auth handled by Istio!
        return Map.of("merchants", List.of());
    }
}
```

## 🔍 Troubleshooting Guide

### Common Issues:

#### 1. 404 Not Found
```bash
# Check Istio routing
kubectl get virtualservice -n opa-keycloak -o yaml

# Verify service exists
kubectl get svc -n opa-keycloak | grep merchant-api
```

#### 2. 403 Forbidden (Auth Issues)
```bash
# Check OPA decisions
kubectl logs -l app=opa-envoy -n opa-keycloak | grep decision | tail -5

# Test OPA policy directly
curl -X POST http://localhost:8181/v1/data/istio/authz/allow -d @test-input.json
```

#### 3. 500 Internal Server Error
```bash
# Check API logs
kubectl logs -l app=merchant-api -n opa-keycloak

# Check sidecar logs
kubectl logs -l app=merchant-api -n opa-keycloak -c istio-proxy
```

## 📈 Scaling Considerations

### Performance Optimization:
- **OPA Policy Caching**: Enable policy caching for better performance
- **Connection Pooling**: Configure Envoy connection pools
- **Resource Limits**: Set appropriate CPU/memory limits

### Security Best Practices:
- **Principle of Least Privilege**: Grant minimum required permissions
- **Regular Policy Reviews**: Audit OPA policies regularly
- **Token Rotation**: Implement short-lived tokens with refresh

### Monitoring:
- **OPA Decision Metrics**: Monitor policy evaluation times
- **API Response Times**: Track latency across all APIs
- **Error Rates**: Monitor 4xx/5xx responses

## 🎉 Benefits of This Setup

### For Developers:
- ✅ **Zero Security Code**: No auth logic in your APIs
- ✅ **Any Language**: Use your preferred tech stack
- ✅ **Fast Development**: Focus only on business logic
- ✅ **Consistent Security**: Same auth across all APIs

### For Operations:
- ✅ **Centralized Security**: Single point of auth control
- ✅ **Policy as Code**: Version-controlled authorization
- ✅ **Observability**: Complete audit trail
- ✅ **Scalability**: Handles thousands of APIs

### For Security:
- ✅ **Zero Trust**: Every request is authenticated/authorized
- ✅ **Fine-Grained Control**: Per-endpoint permissions
- ✅ **Compliance Ready**: Complete audit logs
- ✅ **Policy Testing**: Validate policies before deployment

This setup enables you to build a **polyglot microservices architecture** with **enterprise-grade security** while keeping development simple and fast! 🚀 