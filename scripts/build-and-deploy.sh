#!/bin/bash

# Build and Deploy Employee API
# Usage: ./scripts/build-and-deploy.sh [version]

set -e

# Configuration
SERVICE="employee-api"
REGISTRY="localhost:5000"
LOCATION="./apps/employee-api"
VERSION=${1:-"latest"}
TAG="$VERSION"

echo "Building and deploying $SERVICE:$TAG..."

# Build the Docker image
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ]; then
    echo "Building image on cloud minikube..."
    
    if [ "x${SPOT_INSTANCE_DNS_NAME}" = "x" ]; then
        echo "ERROR: missing environment variable SPOT_INSTANCE_DNS_NAME"
        echo "Aborting"
        exit 1
    fi
    
    eval $(ssh-agent)
    export DOCKER_BUILDKIT=0  # BuildKit doesn't work with containerd compatibility layer
    MINIKUBE_SSH_KEY=${MINIKUBE_SSH_KEY:-~/.config/cloudkube/minikube-ssh-key}
    ssh-add $MINIKUBE_SSH_KEY
    ssh-keygen -R $SPOT_INSTANCE_DNS_NAME:2222  # remove old host key
    ssh-keyscan -p 2222 -H $SPOT_INSTANCE_DNS_NAME >> ~/.ssh/known_hosts  # add new host key
    
    echo "Building image: $REGISTRY/$SERVICE:$TAG"
    docker -H ssh://docker@$SPOT_INSTANCE_DNS_NAME:2222 build -t $REGISTRY/$SERVICE:$TAG $LOCATION
    
    eval $(ssh-agent -k)  # stop ssh agent
else
    echo "Building image on local minikube..."
    minikube ssh "cd $(pwd) && docker build -t $REGISTRY/$SERVICE:$TAG $LOCATION"
fi

echo "Image built successfully: $REGISTRY/$SERVICE:$TAG"

# Update the Kubernetes manifest with the new image tag
if [ "$TAG" != "latest" ]; then
    echo "Updating Kubernetes manifest with version $TAG..."
    sed -i.bak "s|image: $REGISTRY/$SERVICE:.*|image: $REGISTRY/$SERVICE:$TAG|g" k8s/manifests/employee-api.yaml
    rm k8s/manifests/employee-api.yaml.bak 2>/dev/null || true
fi

# Deploy to Kubernetes
echo "Deploying to Kubernetes..."
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