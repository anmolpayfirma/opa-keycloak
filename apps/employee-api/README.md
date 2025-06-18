# Employee API

A simple REST API for employee management with OPA (Open Policy Agent) authorization.

## Features

- RESTful API for employee data
- JWT token-based authentication
- OPA integration for fine-grained authorization
- Health check endpoint
- Docker support

## API Endpoints

- `GET /health` - Health check
- `GET /employees` - List all employees (requires authorization)
- `GET /employees/{id}` - Get specific employee (requires authorization)

## Authorization Rules

- **Managers**: Can access all employee records
- **HR Staff**: Can view and update employee records (no delete)
- **Employees**: Can only view their own records
- **Guests**: No access

## Environment Variables

- `PORT` - Server port (default: 8080)
- `OPA_SERVICE_HOST` - OPA service hostname
- `OPA_SERVICE_PORT` - OPA service port (default: 8181)
- `APP_VERSION` - Application version for health check

## Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run the application
python app.py
```

## Docker Build

```bash
# Build the image
docker build -t employee-api:latest .

# Run the container
docker run -p 8080:8080 employee-api:latest
```

## Testing

```bash
# Health check
curl http://localhost:8080/health

# Get employees (requires valid JWT token)
curl -H "Authorization: Bearer <token>" http://localhost:8080/employees
``` 