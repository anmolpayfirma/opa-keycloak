#!/bin/bash

# Deploy Employee API to Kubernetes
# Usage: ./scripts/deploy.sh [version]

set -e

# Configuration
SERVICE="employee-api"
REGISTRY="localhost:5000"
VERSION=${1:-"latest"}
TAG="$VERSION"

echo "Deploying $SERVICE:$TAG to Kubernetes..."

# Update the Kubernetes manifest with the new image tag
if [ "$TAG" != "latest" ]; then
    echo "Updating Kubernetes manifest with version $TAG..."
    sed -i.bak "s|image: $REGISTRY/$SERVICE:.*|image: $REGISTRY/$SERVICE:$TAG|g" k8s/manifests/employee-api.yaml
    rm k8s/manifests/employee-api.yaml.bak 2>/dev/null || true
fi

# Deploy to Kubernetes
echo "Applying Kubernetes manifests..."
kubectl apply -f k8s/manifests/employee-api.yaml

# Wait for rollout to complete
echo "Waiting for deployment to complete..."
kubectl rollout status deployment/employee-api -n opa-keycloak-practice --timeout=300s

# Get the pod status
echo "Deployment complete! Pod status:"
kubectl get pods -n opa-keycloak-practice -l app=employee-api

echo "✅ $SERVICE:$TAG deployed successfully!"
echo ""
echo "To test the deployment:"
echo "  kubectl port-forward -n opa-keycloak-practice service/employee-api-service 3000:80"
echo "  curl http://localhost:3000/health" 