#!/bin/bash

# Test script to verify Istio setup is working
echo "🧪 Testing OPA-Keycloak with Istio Service Mesh"
echo "================================================"

# Check if opa-demo.local resolves
echo "1. Testing DNS resolution..."
if ping -c 1 opa-demo.local > /dev/null 2>&1; then
    echo "✅ opa-demo.local resolves correctly"
else
    echo "❌ opa-demo.local does not resolve. Check /etc/hosts file"
    exit 1
fi

# Test Keycloak welcome page
echo "2. Testing Keycloak welcome page..."
if curl -s http://opa-demo.local/auth/ | grep -q "Welcome to Keycloak"; then
    echo "✅ Keycloak welcome page accessible"
else
    echo "❌ Keycloak welcome page not accessible"
fi

# Test Keycloak admin console redirect
echo "3. Testing Keycloak admin console..."
ADMIN_REDIRECT=$(curl -s -I http://opa-demo.local/auth/admin/ | grep -i location | cut -d' ' -f2 | tr -d '\r')
if [[ "$ADMIN_REDIRECT" == *"opa-demo.local/auth/admin/master/console/"* ]]; then
    echo "✅ Keycloak admin console redirects correctly"
else
    echo "❌ Keycloak admin console redirect issue: $ADMIN_REDIRECT"
fi

# Test Employee API health
echo "4. Testing Employee API health..."
if curl -s http://opa-demo.local/health | grep -q "healthy"; then
    echo "✅ Employee API health check working"
else
    echo "❌ Employee API health check failed"
fi

# Test Employee API authentication
echo "5. Testing Employee API authentication..."
if curl -s http://opa-demo.local/api/v1/employees | grep -q "Missing or invalid authorization"; then
    echo "✅ Employee API correctly requires authentication"
else
    echo "❌ Employee API authentication check failed"
fi

echo ""
echo "🎉 Test complete! If all tests passed, your Istio setup is working correctly."
echo "📖 Access your services at:"
echo "   - Keycloak: http://opa-demo.local/auth/"
echo "   - Admin Console: http://opa-demo.local/auth/admin/"
echo "   - Employee API: http://opa-demo.local/api/v1/employees"
echo "   - Health Check: http://opa-demo.local/health" 