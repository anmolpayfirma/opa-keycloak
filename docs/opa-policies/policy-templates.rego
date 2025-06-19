# OPA Policy Templates
# Reusable authorization patterns for different API types

package istio.authz

import rego.v1

# =============================================================================
# CORE HELPER FUNCTIONS (Reusable across all APIs)
# =============================================================================

# Check if user is authenticated
is_authenticated if {
	token_payload
	token_payload.exp > time.now_ns() / 1000000000
}

# Extract JWT token payload
token_payload := payload if {
	auth_header := input.attributes.request.http.headers.authorization
	startswith(auth_header, "Bearer ")
	token := substring(auth_header, 7, -1)
	parts := io.jwt.decode(token)
	payload := parts[1]
}

# Check if user has any of the required roles
user_has_role(required_roles) if {
	some role in required_roles
	role in token_payload.realm_access.roles
}

# Check if user has specific permission
user_has_permission(permission) if {
	permission in token_payload.permissions
}

# Get user's tenant/organization ID
user_tenant := token_payload.tenant_id

# Get user's employee/user ID
user_id := token_payload.employee_id

# =============================================================================
# TEMPLATE 1: CRUD API (Standard Resource Management)
# =============================================================================
# Use for: Employee API, Product API, Order API, Customer API

# CRUD API Authorization Template
crud_api_allow(api_path, read_roles, write_roles) if {
	startswith(input.attributes.request.http.path, api_path)
	is_authenticated
	crud_api_permission(read_roles, write_roles)
}

crud_api_permission(read_roles, write_roles) if {
	input.attributes.request.http.method == "GET"
	user_has_role(read_roles)
}

crud_api_permission(read_roles, write_roles) if {
	input.attributes.request.http.method in ["POST", "PUT", "DELETE"]
	user_has_role(write_roles)
}

# Example usage:
# allow if crud_api_allow("/api/v1/employees", ["employee", "manager"], ["manager"])

# =============================================================================
# TEMPLATE 2: ADMIN API (Administrative Functions)
# =============================================================================
# Use for: System API, Configuration API, Analytics API, Audit API

admin_api_allow(api_path, admin_roles) if {
	startswith(input.attributes.request.http.path, api_path)
	is_authenticated
	user_has_role(admin_roles)
}

# Example usage:
# allow if admin_api_allow("/api/v1/system", ["admin", "system-admin"])

# =============================================================================
# TEMPLATE 3: PUBLIC API (Publicly Accessible)
# =============================================================================
# Use for: Catalog API, Documentation API, Status API

public_api_allow(api_path, write_roles) if {
	startswith(input.attributes.request.http.path, api_path)
	public_api_permission(write_roles)
}

public_api_permission(write_roles) if {
	input.attributes.request.http.method == "GET"
	# No authentication required for read operations
}

public_api_permission(write_roles) if {
	input.attributes.request.http.method in ["POST", "PUT", "DELETE"]
	is_authenticated
	user_has_role(write_roles)
}

# Example usage:
# allow if public_api_allow("/api/v1/catalog", ["admin"])

# =============================================================================
# TEMPLATE 4: TENANT/MULTI-TENANT API (Organization-Specific)
# =============================================================================
# Use for: Merchant API, Organization API, Team API

tenant_api_allow(api_path, read_roles, write_roles) if {
	startswith(input.attributes.request.http.path, api_path)
	is_authenticated
	tenant_api_permission(read_roles, write_roles)
	tenant_access_allowed
}

tenant_api_permission(read_roles, write_roles) if {
	input.attributes.request.http.method == "GET"
	user_has_role(read_roles)
}

tenant_api_permission(read_roles, write_roles) if {
	input.attributes.request.http.method in ["POST", "PUT", "DELETE"]
	user_has_role(write_roles)
}

# Tenant isolation - user can only access their own tenant's data
tenant_access_allowed if {
	# Extract tenant ID from URL path (e.g., /api/v1/tenants/{tenant_id}/resources)
	path_parts := split(input.attributes.request.http.path, "/")
	resource_tenant := path_parts[4] # Adjust index based on your URL structure
	user_tenant == resource_tenant
}

tenant_access_allowed if {
	# Super admin can access all tenants
	user_has_role(["super-admin"])
}

# Example usage:
# allow if tenant_api_allow("/api/v1/tenants", ["tenant-user"], ["tenant-admin"])

# =============================================================================
# TEMPLATE 5: USER-SPECIFIC API (Personal Data Access)
# =============================================================================
# Use for: Profile API, Personal Settings API, User Preferences API

user_api_allow(api_path, admin_roles) if {
	startswith(input.attributes.request.http.path, api_path)
	is_authenticated
	user_api_permission(admin_roles)
}

user_api_permission(admin_roles) if {
	# Users can access their own data
	path_parts := split(input.attributes.request.http.path, "/")
	resource_user := path_parts[4] # e.g., /api/v1/users/{user_id}/profile
	user_id == resource_user
}

user_api_permission(admin_roles) if {
	# Admins can access any user's data
	user_has_role(admin_roles)
}

# Example usage:
# allow if user_api_allow("/api/v1/users", ["admin", "hr"])

# =============================================================================
# TEMPLATE 6: HIERARCHICAL API (Department/Team Based)
# =============================================================================
# Use for: Department API, Team API, Project API

hierarchical_api_allow(api_path, read_roles, write_roles) if {
	startswith(input.attributes.request.http.path, api_path)
	is_authenticated
	hierarchical_api_permission(read_roles, write_roles)
	hierarchical_access_allowed
}

hierarchical_api_permission(read_roles, write_roles) if {
	input.attributes.request.http.method == "GET"
	user_has_role(read_roles)
}

hierarchical_api_permission(read_roles, write_roles) if {
	input.attributes.request.http.method in ["POST", "PUT", "DELETE"]
	user_has_role(write_roles)
}

# Hierarchical access - users can access their department/team data
hierarchical_access_allowed if {
	user_department := token_payload.department
	path_parts := split(input.attributes.request.http.path, "/")
	resource_department := path_parts[4] # Adjust based on URL structure
	user_department == resource_department
}

hierarchical_access_allowed if {
	# Managers can access all departments
	user_has_role(["manager", "admin"])
}

# Example usage:
# allow if hierarchical_api_allow("/api/v1/departments", ["employee"], ["manager"])

# =============================================================================
# TEMPLATE 7: TIME-BASED API (Scheduled Access)
# =============================================================================
# Use for: Batch Processing API, Scheduled Reports API

time_based_api_allow(api_path, roles, allowed_hours) if {
	startswith(input.attributes.request.http.path, api_path)
	is_authenticated
	user_has_role(roles)
	time_access_allowed(allowed_hours)
}

time_access_allowed(allowed_hours) if {
	current_hour := time.clock([time.now_ns(), "UTC"])[0]
	current_hour >= allowed_hours[0]
	current_hour <= allowed_hours[1]
}

# Example usage:
# allow if time_based_api_allow("/api/v1/batch", ["admin"], [9, 17])  # 9 AM to 5 PM

# =============================================================================
# TEMPLATE 8: RATE-LIMITED API (Special Access Control)
# =============================================================================
# Use for: External API Gateway, High-Cost Operations

rate_limited_api_allow(api_path, roles, max_requests) if {
	startswith(input.attributes.request.http.path, api_path)
	is_authenticated
	user_has_role(roles)
	# Note: Rate limiting logic would be implemented in Envoy/Istio
	# This is just the authorization check
}

# =============================================================================
# HEALTH CHECK ENDPOINTS (Always Allow)
# =============================================================================

# Health checks should always be accessible
allow if {
	input.attributes.request.http.path == "/health"
}

allow if {
	endswith(input.attributes.request.http.path, "-health")
}

allow if {
	startswith(input.attributes.request.http.path, "/health/")
}

# =============================================================================
# EXAMPLE CONCRETE IMPLEMENTATIONS
# =============================================================================

# Employee API (CRUD Template)
allow if {
	crud_api_allow("/api/v1/employees", ["employee", "manager"], ["manager"])
}

# System API (Admin Template)
allow if {
	admin_api_allow("/api/v1/system", ["admin"])
}

# Catalog API (Public Template)
allow if {
	public_api_allow("/api/v1/catalog", ["admin"])
}

# Merchant API (Tenant Template)
allow if {
	tenant_api_allow("/api/v1/merchants", ["employee", "manager"], ["manager"])
}

# Profile API (User-Specific Template)
allow if {
	user_api_allow("/api/v1/users", ["admin", "hr"])
}

# Department API (Hierarchical Template)
allow if {
	hierarchical_api_allow("/api/v1/departments", ["employee"], ["manager"])
}

# =============================================================================
# DEBUGGING HELPERS
# =============================================================================

# Debug information (remove in production)
debug_info := {
	"user_id": user_id,
	"user_tenant": user_tenant,
	"user_roles": token_payload.realm_access.roles,
	"request_method": input.attributes.request.http.method,
	"request_path": input.attributes.request.http.path,
	"is_authenticated": is_authenticated,
}

# Uncomment for debugging:
# allow if {
#     input.attributes.request.http.path == "/debug"
#     trace(sprintf("Debug info: %v", [debug_info]))
#     false  # Always deny debug endpoint
# }
