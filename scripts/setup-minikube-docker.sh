#!/bin/bash

# Setup Docker compatibility for minikube
# This enables Docker commands to work with containerd in minikube

set -e

echo "🔧 Setting up Docker compatibility for minikube..."

# Apply the compatibility setup
echo "📦 Applying Docker compatibility manifests..."
kubectl apply -f k8s/system/minikube-docker-compatibility.yaml

# Wait for jobs to complete
echo "⏳ Waiting for installation jobs to complete..."
kubectl wait --for=condition=complete job/install-docker-compatibility-tools -n minikube-system --timeout=300s
kubectl wait --for=condition=complete job/replace-docker-binary -n minikube-system --timeout=300s

# Wait for daemon to be ready
echo "🚀 Waiting for nerdctld daemon to be ready..."
kubectl wait --for=condition=available deployment/nerdctld-daemon -n minikube-system --timeout=120s

echo "✅ Docker compatibility setup complete!"
echo ""
echo "You can now use Docker commands in your build scripts."
echo "To verify: ssh into minikube and run 'docker version'"
echo ""
echo "To clean up: kubectl delete namespace minikube-system" 