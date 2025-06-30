#!/bin/bash

# Build and Update Script
# Usage: ./build-update.sh <microservice> <tag>
# Builds Docker images and updates Kubernetes deployments

set -e

# Parse arguments
BUILD_ONLY=false
SERVICE=""
TAG="latest"

# Parse all arguments
for arg in "$@"; do
    if [ "$arg" = "--build-only" ]; then
        BUILD_ONLY=true
    elif [ -z "$SERVICE" ]; then
        SERVICE="$arg"
    elif [ "$TAG" = "latest" ]; then
        TAG="$arg"
    fi
done

if [ -z "$SERVICE" ] || [ $# -gt 3 ]; then
    echo "Usage: $0 <microservice> [tag] [--build-only]"
    echo ""
    echo "Options:"
    echo "  tag             Image tag (defaults to 'latest')"
    echo "  --build-only    Only build the image, don't update deployment"
    echo ""
    echo "Available services:"
    for service_dir in apps/*/; do
        if [ -d "$service_dir" ] && [ -f "${service_dir}Dockerfile" ]; then
            service_name=$(basename "$service_dir")
            echo "  - $service_name"
        fi
    done
    exit 1
fi
SERVICE_DIR="apps/$SERVICE"
REGISTRY="${REGISTRY:-localhost:5000}"
IMAGE_NAME="$REGISTRY/$SERVICE:$TAG"
NAMESPACE="${NAMESPACE:-opa-keycloak}"

# Validate service exists
if [ ! -d "$SERVICE_DIR" ]; then
    echo "Error: Service directory not found: $SERVICE_DIR"
    exit 1
fi

if [ ! -f "$SERVICE_DIR/Dockerfile" ]; then
    echo "Error: Dockerfile not found in: $SERVICE_DIR"
    exit 1
fi

echo "🐳 Building $IMAGE_NAME..."

# Check if using cloud minikube
if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ] && [ -n "$SPOT_INSTANCE_DNS_NAME" ]; then
    echo "Using cloud minikube at $SPOT_INSTANCE_DNS_NAME"
    
    # Your original pattern (silent):
    eval $(ssh-agent) > /dev/null 2>&1
    export DOCKER_BUILDKIT=0
    MINIKUBE_SSH_KEY=${MINIKUBE_SSH_KEY:-~/.config/cloudkube/minikube-ssh-key}
    ssh-add $MINIKUBE_SSH_KEY > /dev/null 2>&1
    ssh-keygen -R $SPOT_INSTANCE_DNS_NAME:2222 > /dev/null 2>&1
    ssh-keyscan -p 2222 -H $SPOT_INSTANCE_DNS_NAME >> ~/.ssh/known_hosts 2>/dev/null
    docker -H ssh://docker@$SPOT_INSTANCE_DNS_NAME:2222 build -t $IMAGE_NAME $SERVICE_DIR
    eval $(ssh-agent -k) > /dev/null 2>&1
else
    # Local build
    export DOCKER_BUILDKIT=0
    docker build -t $IMAGE_NAME $SERVICE_DIR
fi

echo "✅ Built: $IMAGE_NAME"

# Skip deployment update if --build-only flag is set
if [ "$BUILD_ONLY" = true ]; then
    echo "🔧 Build-only mode: Skipping deployment update"
    exit 0
fi

# Update Kubernetes deployment
echo "🚀 Updating deployment..."

# Check if deployment exists
DEPLOYMENT_NAME=""
case $SERVICE in
    "employee-api")
        DEPLOYMENT_NAME="employee-api"
        ;;
    "merchant-api")
        DEPLOYMENT_NAME="merchant-api"
        ;;
    *)
        # For future services, assume deployment name matches service name
        DEPLOYMENT_NAME="$SERVICE"
        ;;
esac

# Check if deployment exists in the namespace
if kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE > /dev/null 2>&1; then
    echo "Updating deployment $DEPLOYMENT_NAME with image $IMAGE_NAME"
    
    # For cloud minikube, ensure we use the right image name format
    if [ "$MINIKUBE_IN_THE_CLOUD" = "y" ]; then
        # Use the registry prefix for cloud minikube
        DEPLOY_IMAGE_NAME="$IMAGE_NAME"
    else
        DEPLOY_IMAGE_NAME="$IMAGE_NAME"
    fi
    
    # Update the container image (container name matches service name)
    kubectl set image deployment/$DEPLOYMENT_NAME $SERVICE=$DEPLOY_IMAGE_NAME -n $NAMESPACE
    
    # Wait for rollout to complete
    echo "Waiting for rollout to complete..."
    if kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=300s; then
        echo "✅ Deployment updated successfully!"
        
        # Show current status
        echo ""
        echo "📊 Current deployment status:"
        kubectl get pods -l app=$SERVICE -n $NAMESPACE
    else
        echo "❌ Rollout failed or timed out"
        echo "Current deployment status:"
        kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE
        exit 1
    fi
else
    echo "⚠️  Deployment $DEPLOYMENT_NAME not found in namespace $NAMESPACE"
    echo "Available deployments:"
    kubectl get deployments -n $NAMESPACE 2>/dev/null || echo "No deployments found or namespace doesn't exist"
    echo ""
    echo "💡 You may need to deploy with Helm first:"
    echo "   ./scripts/helm-deploy-clean.sh"
fi 