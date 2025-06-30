# Employee API with PostgreSQL Integration

A production-ready Employee API with PostgreSQL database backend, featuring full CRUD operations, proper error handling, and seamless integration with the OPA + Keycloak authorization system.

## 🚀 Features

### Database Integration
- **PostgreSQL 15** with persistent storage
- **Connection pooling** ready for production
- **Database migrations** and seeding
- **Health checks** with database connectivity verification
- **Proper error handling** for database operations

### API Capabilities
- **Full CRUD operations** (Create, Read, Update, Delete)
- **Department filtering** with query parameters
- **JSON API** with proper HTTP status codes
- **CORS support** for web applications
- **Health monitoring** endpoint

### Security & Production Ready
- **Non-root container** execution
- **Resource limits** and requests
- **Liveness and readiness probes**
- **Graceful error handling**
- **SQL injection protection** with parameterized queries

## 📊 Database Schema

### Employees Table
```sql
CREATE TABLE employees (
    id VARCHAR(20) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    department VARCHAR(50) NOT NULL,
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Departments Table
```sql
CREATE TABLE departments (
    id VARCHAR(20) PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## 🔗 API Endpoints

### Employee Operations
| Method | Endpoint | Description | Example |
|--------|----------|-------------|---------|
| `GET` | `/api/v1/employees` | List all employees | `curl http://api/api/v1/employees` |
| `GET` | `/api/v1/employees?department=Engineering` | Filter by department | `curl http://api/api/v1/employees?department=Engineering` |
| `GET` | `/api/v1/employees/{id}` | Get specific employee | `curl http://api/api/v1/employees/EMP001` |
| `POST` | `/api/v1/employees` | Create new employee | See [Create Example](#create-employee) |
| `PUT` | `/api/v1/employees/{id}` | Update employee | See [Update Example](#update-employee) |
| `DELETE` | `/api/v1/employees/{id}` | Delete employee | `curl -X DELETE http://api/api/v1/employees/EMP001` |

### Department Operations
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/departments` | List all departments |

### System Operations
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Health check with database status |

## 📝 API Examples

### Create Employee
```bash
curl -X POST http://api/api/v1/employees \
  -H "Content-Type: application/json" \
  -d '{
    "id": "EMP999",
    "name": "New Employee",
    "department": "Engineering",
    "email": "new@company.com"
  }'
```

**Response:**
```json
{
  "employee": {
    "id": "EMP999",
    "name": "New Employee",
    "department": "Engineering",
    "email": "new@company.com",
    "created_at": "2024-01-15T10:30:00Z",
    "updated_at": "2024-01-15T10:30:00Z"
  }
}
```

### Update Employee
```bash
curl -X PUT http://api/api/v1/employees/EMP999 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Updated Employee Name",
    "email": "updated@company.com"
  }'
```

### List Employees Response
```json
{
  "employees": [
    {
      "id": "EMP001",
      "name": "John Doe",
      "department": "Engineering",
      "email": "john.doe@company.com",
      "created_at": "2024-01-15T09:00:00Z",
      "updated_at": "2024-01-15T09:00:00Z"
    }
  ],
  "count": 6
}
```

### Health Check Response
```json
{
  "status": "healthy",
  "service": "Employee API",
  "version": "3.0.0",
  "database": "connected",
  "authorization": "handled_by_kong"
}
```

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

## 🔧 Configuration

### Environment Variables
| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | API server port |
| `DB_HOST` | `postgresql-service` | PostgreSQL hostname |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_NAME` | `employee_api` | Database name |
| `DB_USER` | `employee_api` | Database username |
| `DB_PASSWORD` | `employee123` | Database password |
| `APP_VERSION` | `latest` | Application version |

### Database Configuration
The application connects to PostgreSQL using the following connection string:
```
postgresql://employee_api:employee123@postgresql-service:5432/employee_api
```

## 🚀 Deployment

### Prerequisites
- Kubernetes cluster with PostgreSQL deployed
- Docker registry access
- `kubectl` configured

### Build and Deploy
```bash
# Build the Docker image
./build-update.sh employee-api latest

# Deploy to Kubernetes (via Helm)
./scripts/helm-deploy-clean.sh
```

### Using the Deployment Script
```bash
# Deploy complete PostgreSQL-enabled system
./scripts/deploy-postgres.sh
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

### Authorization Test
```bash
./scripts/test-authorization-postgres.sh
```

### Manual Testing
```bash
# Get API pod
API_POD=$(kubectl get pod -l app=employee-api -o jsonpath='{.items[0].metadata.name}')

# Test health endpoint
kubectl exec $API_POD -- curl -s http://localhost:8080/health

# Test employee listing
kubectl exec $API_POD -- curl -s http://localhost:8080/api/v1/employees
```

## 📊 Monitoring

### Health Checks
The API provides comprehensive health checks:
- **Liveness probe**: `/health` endpoint
- **Readiness probe**: `/health` endpoint with database connectivity
- **Database status**: Included in health response

### Metrics
- Response times for all endpoints
- Database connection status
- Error rates by endpoint
- Request counts by method

## 🔍 Troubleshooting

### Common Issues

#### Database Connection Failed
```bash
# Check PostgreSQL pod status
kubectl get pods -l app=postgresql

# Check database connectivity
kubectl run db-test --image=postgres:15-alpine --rm -i --restart=Never -- \
  psql -h postgresql-service -U postgres -d opa_demo -c "SELECT 1;"
```

#### API Pod Not Starting
```bash
# Check pod logs
kubectl logs -l app=employee-api

# Check resource constraints
kubectl describe pod -l app=employee-api
```

#### Slow Database Performance
```bash
# Check database size
kubectl run db-size-check --image=postgres:15-alpine --rm -i --restart=Never -- \
  psql -h postgresql-service -U postgres -d employee_api -c \
  "SELECT pg_size_pretty(pg_database_size('employee_api'));"

# Check active connections
kubectl run db-connections --image=postgres:15-alpine --rm -i --restart=Never -- \
  psql -h postgresql-service -U postgres -d employee_api -c \
  "SELECT count(*) FROM pg_stat_activity;"
```

## 🔐 Security

### Database Security
- **Separate database users** for each service
- **Encrypted passwords** stored in Kubernetes secrets
- **Network isolation** within Kubernetes cluster
- **Parameterized queries** prevent SQL injection

### API Security
- **Authorization handled by Istio Gateway with OPA**
- **Non-root container execution**
- **Resource limits** prevent resource exhaustion
- **CORS configuration** for web security

## 📈 Performance

### Database Optimizations
- **Indexed primary keys** for fast lookups
- **Connection reuse** for better performance
- **Prepared statements** for query optimization
- **Resource limits** prevent memory leaks

### API Optimizations
- **Efficient JSON serialization**
- **Proper HTTP caching headers**
- **Graceful error handling**
- **Resource-aware deployment**

## 🔄 Backup and Recovery

### Database Backup
```bash
# Create backup
kubectl exec -i $(kubectl get pod -l app=postgresql -o jsonpath='{.items[0].metadata.name}') -- \
  pg_dump -U postgres employee_api > backup-$(date +%Y%m%d).sql

# Restore backup
kubectl exec -i $(kubectl get pod -l app=postgresql -o jsonpath='{.items[0].metadata.name}') -- \
  psql -U postgres employee_api < backup-20240115.sql
```

### Persistent Volume
- **5Gi persistent storage** ensures data persistence
- **Automatic volume binding** in Kubernetes
- **Data survives pod restarts** and deployments

## 🚀 Production Considerations

### Scaling
- **Horizontal pod autoscaling** based on CPU/memory
- **Database connection pooling** for multiple replicas
- **Load balancing** through Kubernetes services

### Monitoring
- **Prometheus metrics** for observability
- **Grafana dashboards** for visualization
- **Alert manager** for critical issues

### Security
- **Regular security updates** for base images
- **Database credential rotation**
- **Network policies** for pod-to-pod communication
- **RBAC** for Kubernetes access control

---

## 📚 Additional Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Python psycopg2 Documentation](https://www.psycopg.org/docs/)
- [OPA + Keycloak Integration Guide](../docs/OPA-Keycloak-Practice-Guide.md) 