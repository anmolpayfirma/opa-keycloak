# OPA + Keycloak REST API Authorization Practice

## Overview
This hands-on exercise demonstrates how to integrate Open Policy Agent (OPA) with Keycloak for REST API authorization in a Kubernetes environment using minikube.

## Scenario
We'll build a simple **Employee Management API** with the following authorization requirements:
- **Managers** can view, create, update, and delete all employee records
- **HR Staff** can view and update employee records but cannot delete
- **Employees** can only view their own records
- **Guests** have no access

## Prerequisites
- minikube running
- kubectl configured
- Basic understanding of Kubernetes, OPA, and Keycloak

## Architecture
```
Client Request → Ingress → Employee API → OPA Service → Policy Decision
                                    ↓
                              Keycloak Token Validation
```

## Step 1: Create Practice Namespace

```bash
kubectl create namespace opa-keycloak-practice
kubectl config set-context --current --namespace=opa-keycloak-practice
```

## Step 2: Deploy Keycloak

### Keycloak Deployment
```yaml
# keycloak-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: opa-keycloak-practice
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:23.0
        args: ["start-dev"]
        env:
        - name: KEYCLOAK_ADMIN
          value: "admin"
        - name: KEYCLOAK_ADMIN_PASSWORD
          value: "admin123"
        - name: KC_HTTP_PORT
          value: "8080"
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /realms/master
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak-service
  namespace: opa-keycloak-practice
spec:
  selector:
    app: keycloak
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
```

Deploy Keycloak:
```bash
kubectl apply -f keycloak-deployment.yaml
```

### Expose Keycloak for Configuration
```bash
kubectl port-forward service/keycloak-service 8082:8080 &
```

```fish
kubectl port-forward service/keycloak-service 8082:8080 &
```

Wait for Keycloak to be ready:
```bash
kubectl wait --for=condition=ready pod -l app=keycloak --timeout=300s
```

## Step 3: Configure Keycloak

You have two options to configure Keycloak:
1. **Manual UI Configuration (Recommended)**: Step-by-step setup through the Admin Console - great for learning
2. **JSON Import**: Faster bulk configuration using a pre-defined JSON file

### Configure Keycloak via Admin Console (Recommended)

#### Step 3.1: Access Admin Console
- Open http://localhost:8082
- Login with username: `admin`, password: `admin123`

#### Step 3.2: Create New Realm
1. Click on the realm dropdown (currently showing "master") in the top-left
2. Click "Create Realm"
3. Enter realm name: `employee-management`
4. Click "Create"

#### Step 3.3: Create Realm Roles
1. In the left sidebar, click "Realm roles"
2. Click "Create role" and add the following roles one by one:
   - Role name: `manager` → Click "Save"
   - Role name: `hr-staff` → Click "Save"  
   - Role name: `employee` → Click "Save"
   - Role name: `guest` → Click "Save"

#### Step 3.4: Create Client
1. In the left sidebar, click "Clients"
2. Click "Create client"
3. Fill in the details:
   - Client type: `OpenID Connect`
   - Client ID: `employee-api`
   - Click "Next"
4. Configure capability:
   - Client authentication: `On` (This enables client secret requirement)
   - Authorization: `Off`
   - Standard flow: `Off`
   - Direct access grants: `On`
   - Service accounts roles: `On`
   - Click "Next", then "Save"
5. **Important**: After saving, go to the "Credentials" tab to find your client secret
   - Copy the "Client secret" value - you'll need this for API calls

#### Step 3.5: Create Users
1. In the left sidebar, click "Users"
2. Click "Create new user"

**Manager User:**
- Username: `john.manager`
- First name: `John`
- Last name: `Manager`
- Click "Create"
- Go to "Credentials" tab → Click "Set password"
  - Password: `password123`
  - Temporary: `Off`
  - Click "Save"
- Go to "Role mapping" tab → Click "Assign role"
  - Select `manager` role → Click "Assign"
- Go to "Attributes" tab → Click "Add attribute"
  - Key: `employee_id`, Value: `EMP001` → Click "Save"
  - Key: `department`, Value: `Engineering` → Click "Save"

**HR Staff User:**
- Username: `jane.hr`
- First name: `Jane`
- Last name: `HR`
- Click "Create"
- Go to "Credentials" tab → Click "Set password"
  - Password: `password123`
  - Temporary: `Off`
  - Click "Save"
- Go to "Role mapping" tab → Click "Assign role"
  - Select `hr-staff` role → Click "Assign"
- Go to "Attributes" tab → Click "Add attribute"
  - Key: `employee_id`, Value: `EMP002` → Click "Save"
  - Key: `department`, Value: `HR` → Click "Save"

**Employee User:**
- Username: `bob.employee`
- First name: `Bob`
- Last name: `Employee`
- Click "Create"
- Go to "Credentials" tab → Click "Set password"
  - Password: `password123`
  - Temporary: `Off`
  - Click "Save"
- Go to "Role mapping" tab → Click "Assign role"
  - Select `employee` role → Click "Assign"
- Go to "Attributes" tab → Click "Add attribute"
  - Key: `employee_id`, Value: `EMP003` → Click "Save"
  - Key: `department`, Value: `Engineering` → Click "Save"

#### Understanding Client Authentication

With "Client authentication" enabled, Keycloak requires both a client ID and client secret for token requests. This provides additional security by ensuring only authorized applications can obtain tokens.

**Key Points:**
- Client ID: `employee-api` (public identifier)
- Client Secret: Generated by Keycloak (private credential)
- Both are required for password grant type requests
- The client secret can be found in the client's "Credentials" tab

### Alternative: Import Realm via JSON Configuration

If you prefer to use a JSON configuration file instead of manual UI setup:

#### Step 3.6: Create Realm Configuration File
```bash
# Create realm configuration file
cat > realm-config.json << 'EOF'
{
  "realm": "employee-management",
  "enabled": true,
  "registrationAllowed": false,
  "resetPasswordAllowed": true,
  "clients": [
    {
      "clientId": "employee-api",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "bearerOnly": true,
      "serviceAccountsEnabled": true,
      "directAccessGrantsEnabled": true,
      "clientAuthenticatorType": "client-secret",
      "secret": "your-client-secret-here"
    }
  ],
  "roles": {
    "realm": [
      {"name": "manager"},
      {"name": "hr-staff"},
      {"name": "employee"},
      {"name": "guest"}
    ]
  },
  "users": [
    {
      "username": "john.manager",
      "enabled": true,
      "credentials": [{"type": "password", "value": "password123", "temporary": false}],
      "realmRoles": ["manager"],
      "attributes": {
        "employee_id": ["EMP001"],
        "department": ["Engineering"]
      }
    },
    {
      "username": "jane.hr",
      "enabled": true,
      "credentials": [{"type": "password", "value": "password123", "temporary": false}],
      "realmRoles": ["hr-staff"],
      "attributes": {
        "employee_id": ["EMP002"],
        "department": ["HR"]
      }
    },
    {
      "username": "bob.employee",
      "enabled": true,
      "credentials": [{"type": "password", "value": "password123", "temporary": false}],
      "realmRoles": ["employee"],
      "attributes": {
        "employee_id": ["EMP003"],
        "department": ["Engineering"]
      }
    }
  ]
}
EOF
```

#### Step 3.7: Import Realm Configuration

**Option A: Import via Admin Console**
1. In Keycloak Admin Console, click on the realm dropdown
2. Click "Create Realm"
3. Instead of typing a realm name, click "Browse..." 
4. Select the `realm-config.json` file you just created
5. Click "Create"

**Option B: Import via Keycloak Admin CLI (if available)**
```bash
# First, get into the Keycloak pod
kubectl exec -it deployment/keycloak -- bash

# Inside the pod, use the Admin CLI
/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8082 --realm master --user admin --password admin123

# Import the realm (you'll need to copy the JSON file into the pod first)
/opt/keycloak/bin/kcadm.sh create realms -f /path/to/realm-config.json
```

**Option C: Copy JSON file to pod and import**
```bash
# Copy the JSON file to the Keycloak pod
kubectl cp realm-config.json $(kubectl get pod -l app=keycloak -o jsonpath='{.items[0].metadata.name}'):/tmp/realm-config.json

# Execute the import
kubectl exec -it deployment/keycloak -- /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8082 --realm master --user admin --password admin123

kubectl exec -it deployment/keycloak -- /opt/keycloak/bin/kcadm.sh create realms -f /tmp/realm-config.json
```

> **Note**: Choose either the manual UI approach (Steps 3.1-3.5) OR the JSON import approach (Steps 3.6-3.7), not both.

## Step 4: Deploy OPA

### OPA ConfigMap with Policies
```yaml
# opa-policies.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: opa-policies
  namespace: opa-keycloak-practice
data:
  policy.rego: |
    package system.authz
    
    default allow := false
    
    allow if {
        valid_token
        has_permission
    }
    
    valid_token if {
        input.token
        count(io.jwt.decode(input.token)) == 3
    }
    
    user := payload if {
        [_, payload, _] := io.jwt.decode(input.token)
    }
    
    has_permission if {
        "manager" in user.realm_access.roles
    }
    
    has_permission if {
        "hr-staff" in user.realm_access.roles
        input.method != "DELETE"
    }
    
    has_permission if {
        "employee" in user.realm_access.roles
        input.method == "GET"
        input.path == sprintf("/employees/%s", [user.employee_id])
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: opa
  namespace: opa-keycloak-practice
spec:
  replicas: 1
  selector:
    matchLabels:
      app: opa
  template:
    metadata:
      labels:
        app: opa
    spec:
      containers:
      - name: opa
        image: openpolicyagent/opa:latest-envoy
        ports:
        - containerPort: 8181
        - containerPort: 9191
        args:
          - "run"
          - "--server"
          - "--addr=0.0.0.0:8181"
          - "/policies/policy.rego"
        volumeMounts:
        - name: opa-policies
          mountPath: /policies
        env:
        - name: OPA_LOG_LEVEL
          value: "debug"
      volumes:
      - name: opa-policies
        configMap:
          name: opa-policies
---
apiVersion: v1
kind: Service
metadata:
  name: opa-service
  namespace: opa-keycloak-practice
spec:
  selector:
    app: opa
  ports:
  - name: http
    port: 8181
    targetPort: 8181
  - name: grpc
    port: 9191
    targetPort: 9191
```

Deploy OPA:
```bash
kubectl apply -f opa-policies.yaml
```

## Step 5: Deploy Sample Employee API

### Employee API with OPA Integration
```yaml
# employee-api.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: employee-api
  namespace: opa-keycloak-practice
spec:
  replicas: 1
  selector:
    matchLabels:
      app: employee-api
  template:
    metadata:
      labels:
        app: employee-api
    spec:
      containers:
      - name: employee-api
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: api-config
          mountPath: /etc/nginx/conf.d/default.conf
          subPath: nginx.conf
        - name: api-content
          mountPath: /usr/share/nginx/html
      volumes:
      - name: api-config
        configMap:
          name: api-config
      - name: api-content
        configMap:
          name: api-content
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config
  namespace: opa-keycloak-practice
data:
  nginx.conf: |
    server {
        listen 80;
        
        location /auth {
            internal;
            proxy_pass http://opa-service:8181/v1/data/system/authz/allow;
            proxy_method POST;
            proxy_set_header Content-Type application/json;
            proxy_set_body '{"input":{"method":"$request_method","path":"$request_uri","token":"$http_authorization"}}';
        }
        
        location /employees {
            auth_request /auth;
            proxy_pass http://localhost:3000;
        }
        
        location / {
            return 200 "Employee API Server Running";
            add_header Content-Type text/plain;
        }
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-content
  namespace: opa-keycloak-practice
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head><title>Employee API</title></head>
    <body>
        <h1>Employee Management API</h1>
        <p>Protected by OPA + Keycloak</p>
    </body>
    </html>
---
apiVersion: v1
kind: Service
metadata:
  name: employee-api-service
  namespace: opa-keycloak-practice
spec:
  selector:
    app: employee-api
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
```

Deploy the API:
```bash
kubectl apply -f employee-api.yaml
```

## Step 6: Testing the Integration

### Get Access Token

**First, get your client secret from Keycloak:**
1. Go to http://localhost:8082 → Administration Console
2. Navigate to Clients → employee-api → Credentials tab
3. Copy the "Client secret" value

```bash
# Set your client secret (replace with actual value from Keycloak)
export CLIENT_SECRET="your-client-secret-here"

# Get token for manager
MANAGER_TOKEN=$(curl -s -X POST \
  http://localhost:8082/realms/employee-management/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=employee-api&client_secret=$CLIENT_SECRET&username=john.manager&password=password123" \
  | jq -r '.access_token')

# Get token for employee
EMPLOYEE_TOKEN=$(curl -s -X POST \
  http://localhost:8082/realms/employee-management/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=employee-api&client_secret=$CLIENT_SECRET&username=bob.employee&password=password123" \
  | jq -r '.access_token')
```

```fish
# Fish shell version
# Set your client secret (replace with actual value from Keycloak)
set -x CLIENT_SECRET "your-client-secret-here"

# Get token for manager
set MANAGER_TOKEN (curl -s -X POST \
  http://localhost:8082/realms/employee-management/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=employee-api&client_secret=$CLIENT_SECRET&username=john.manager&password=password123" \
  | jq -r '.access_token')

# Get token for employee
set EMPLOYEE_TOKEN (curl -s -X POST \
  http://localhost:8082/realms/employee-management/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=employee-api&client_secret=$CLIENT_SECRET&username=bob.employee&password=password123" \
  | jq -r '.access_token')
```

### Port Forward API Service
```bash
kubectl port-forward service/employee-api-service 3000:80 &
```

### Test Authorization Scenarios

#### Test 1: Manager Access (Should Work)
```bash
curl -H "Authorization: Bearer $MANAGER_TOKEN" \
     http://localhost:3000/employees
```

#### Test 2: Employee Access to Own Record (Should Work)
```bash
curl -H "Authorization: Bearer $EMPLOYEE_TOKEN" \
     http://localhost:3000/employees/EMP003
```

#### Test 3: Employee Access to Other Record (Should Fail)
```bash
curl -H "Authorization: Bearer $EMPLOYEE_TOKEN" \
     http://localhost:3000/employees/EMP001
```

#### Test 4: Unauthenticated Access (Should Fail)
```bash
curl http://localhost:3000/employees
```

## Step 7: Monitoring and Debugging

### Check OPA Logs
```bash
kubectl logs -l app=opa -f
```

### Check API Logs
```bash
kubectl logs -l app=employee-api -f
```

### Test Policy Directly
```bash
# Port forward OPA
kubectl port-forward service/opa-service 8181:8181 &

# Test policy decision
curl -X POST http://localhost:8181/v1/data/system/authz/allow \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "method": "GET",
      "path": "/employees/EMP001",
      "token": "'$MANAGER_TOKEN'"
    }
  }'
```

## Step 8: Advanced Scenarios

### Update Policy for Department-Based Access
```bash
kubectl edit configmap opa-policies
```

Add department-based rules:
```rego
# Allow HR to access all employee records
has_permission if {
    "hr-staff" in user.realm_access.roles
    input.method == "GET"
    startswith(input.path, "/employees")
}

# Allow managers to access employees in their department
has_permission if {
    "manager" in user.realm_access.roles
    input.method in ["GET", "PUT"]
    employee_id := split(input.path, "/")[2]
    employee_department == user.department
}
```

### Test Token Expiration
```bash
# Wait for token to expire and test
sleep 3600
curl -H "Authorization: Bearer $MANAGER_TOKEN" \
     http://localhost:3000/employees
```

## Step 9: Cleanup

```bash
kubectl delete namespace opa-keycloak-practice
```

## Key Learning Points

1. **Token Validation**: OPA validates JWT tokens from Keycloak
2. **Policy Enforcement**: Fine-grained authorization based on roles and attributes
3. **Service Pattern**: OPA runs as a separate service for policy decisions
4. **Real-time Decisions**: Every API call goes through authorization check
5. **Attribute-Based Access Control**: Using user attributes for access decisions

## Troubleshooting

### Common Issues
- **Token Invalid**: Check Keycloak realm configuration
- **Policy Denied**: Verify OPA policy syntax and logic
- **Connection Refused**: Ensure all services are running and accessible

### Debug Commands
```bash
# Check pod status
kubectl get pods -o wide

# Describe failing pods
kubectl describe pod <pod-name>

# Check service endpoints
kubectl get endpoints

# Test network connectivity
kubectl run debug --image=busybox -it --rm -- sh
```

## Next Steps

1. Implement more complex policies with time-based access
2. Add audit logging for authorization decisions
3. Integrate with external data sources for policy decisions
4. Implement policy testing and CI/CD integration
5. Explore OPA Gatekeeper for Kubernetes admission control

---

*This exercise provides a solid foundation for understanding OPA and Keycloak integration in a microservices environment.*