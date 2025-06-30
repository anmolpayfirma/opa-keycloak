#!/bin/bash

# Setup SSH tunnel for cloud minikube access
# This script sets up port forwarding for Istio Gateway access

echo "🔗 Setting up SSH tunnel for cloud minikube..."

# Configuration
MINIKUBE_SSH_KEY=${MINIKUBE_SSH_KEY:-~/.config/cloudkube/minikube-ssh-key}
REMOTE_HOST=${SPOT_INSTANCE_DNS_NAME:-""}
SSH_PORT=2222
LOCAL_PORT=80
REMOTE_PORT=31772  # NodePort for Istio Gateway

# Validate configuration
if [ -z "$REMOTE_HOST" ]; then
    echo "❌ Error: SPOT_INSTANCE_DNS_NAME environment variable is required"
    echo "   Please set it to your cloud minikube hostname"
    exit 1
fi

if [ ! -f "$MINIKUBE_SSH_KEY" ]; then
    echo "❌ Error: SSH key not found at $MINIKUBE_SSH_KEY"
    exit 1
fi

echo "📋 Tunnel Configuration:"
echo "   Remote host: $REMOTE_HOST:$SSH_PORT"
echo "   Local port: $LOCAL_PORT"
echo "   Remote port: $REMOTE_PORT (Istio Gateway)"
echo "   SSH key: $MINIKUBE_SSH_KEY"
echo ""

# Kill any existing tunnels
echo "🧹 Cleaning up existing tunnels..."
pkill -f "ssh.*$REMOTE_HOST.*$LOCAL_PORT:" 2>/dev/null || true

# Check if port 80 is available
if lsof -ti:$LOCAL_PORT >/dev/null 2>&1; then
    echo "⚠️  Port $LOCAL_PORT is already in use. Attempting to free it..."
    sudo lsof -ti:$LOCAL_PORT | xargs sudo kill -9 2>/dev/null || true
    sleep 2
fi

# Set up the tunnel
echo "🚀 Establishing SSH tunnel..."
echo "   This will forward localhost:$LOCAL_PORT -> $REMOTE_HOST:$REMOTE_PORT"

# Check if running as root for port 80
if [ "$EUID" -ne 0 ] && [ "$LOCAL_PORT" -lt 1024 ]; then
    echo "🔐 Port $LOCAL_PORT requires sudo privileges..."
    sudo ssh -i "$MINIKUBE_SSH_KEY" \
        -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        -L $LOCAL_PORT:192.168.49.2:$REMOTE_PORT \
        -N docker@$REMOTE_HOST -p $SSH_PORT &
else
    ssh -i "$MINIKUBE_SSH_KEY" \
        -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        -L $LOCAL_PORT:192.168.49.2:$REMOTE_PORT \
        -N docker@$REMOTE_HOST -p $SSH_PORT &
fi

TUNNEL_PID=$!
echo "✅ Tunnel established (PID: $TUNNEL_PID)"
echo ""
echo "🌐 You can now access services at:"
echo "   http://opa-demo.local/auth/          (Keycloak)"
echo "   http://opa-demo.local/api/v1/employees (Employee API)"
echo "   http://opa-demo.local/api/v1/merchants (Merchant API)"
echo "   http://opa-demo.local/health         (Health check)"
echo ""
echo "🛑 To stop the tunnel: kill $TUNNEL_PID"

# Keep the script running to maintain the tunnel
wait $TUNNEL_PID 