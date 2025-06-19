package istio.authz

import rego.v1

# UmerchantUservice API Authorization Policy
# Generated automatically by add-new-api.sh

# Main authorization rule for merchant-service
allow if {
    is_merchant_api_request
    is_authenticated
    has_merchant_permission
}

# Check if request is for merchant-service
is_merchant_api_request if {
    startswith(input.attributes.request.http.path, "/api/v1/merchants")
}


# Tenant API - Tenant-specific access
has_merchant_permission if {
    input.attributes.request.http.method == "GET"
    user_has_role(["employee", "manager", "tenant-user"])
    # Add tenant isolation logic here
}

has_merchant_permission if {
    input.attributes.request.http.method in ["POST", "PUT", "DELETE"]
    user_has_role(["manager", "tenant-admin"])
    # Add tenant isolation logic here
}

# Helper function to check user roles (reusable)
user_has_role(required_roles) if {
    some role in required_roles
    role in token_payload.realm_access.roles
}

# Extract token payload (reusable)
token_payload := payload if {
    auth_header := input.attributes.request.http.headers.authorization
    token := substring(auth_header, 7, -1)  # Remove "Bearer "
    parts := io.jwt.decode(token)
    payload := parts[1]
}
