#!/bin/bash

# Build script for auth service
set -e

# Configuration
SERVICE="auth-service"
REGISTRY="localhost:5000"
LOCATION="./apps/auth-service"
VERSION=${1:-"v1.0.0"}
TAG="$VERSION"

echo "Building $SERVICE:$TAG..."

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

echo "✅ Image built successfully: $REGISTRY/$SERVICE:$TAG" 