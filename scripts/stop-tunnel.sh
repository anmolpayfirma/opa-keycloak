#!/bin/bash

# Stop SSH tunnel for cloud minikube access

echo "🛑 Stopping SSH tunnels..."

# Configuration
REMOTE_HOST=${SPOT_INSTANCE_DNS_NAME:-""}
LOCAL_PORT=80

if [ -n "$REMOTE_HOST" ]; then
    echo "   Stopping tunnels to $REMOTE_HOST..."
    pkill -f "ssh.*$REMOTE_HOST.*$LOCAL_PORT:" 2>/dev/null || true
else
    echo "   Stopping all SSH tunnels on port $LOCAL_PORT..."
    pkill -f "ssh.*-L $LOCAL_PORT:" 2>/dev/null || true
fi

# Also kill any processes using port 80
if lsof -ti:$LOCAL_PORT >/dev/null 2>&1; then
    echo "   Freeing port $LOCAL_PORT..."
    sudo lsof -ti:$LOCAL_PORT | xargs sudo kill -9 2>/dev/null || true
fi

echo "✅ Tunnel cleanup complete" 