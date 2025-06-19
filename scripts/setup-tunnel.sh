#!/bin/bash

# Setup SSH tunnel for both Kubernetes API and Istio Gateway access
# This script sets up port forwarding for:
# - Port 8443: Kubernetes API server
# - Port 80: Istio Gateway (requires sudo)

echo "Setting up SSH tunnel for OPA-Keycloak demo with Istio..."
echo "This will forward:"
echo "  - Port 8443 (Kubernetes API)"
echo "  - Port 80 -> 30268 (Istio Gateway)"
echo ""

# Check if running as root for port 80
if [ "$EUID" -ne 0 ]; then
    echo "Note: Port 80 requires sudo privileges."
    echo "Please run with sudo or enter your password when prompted."
    echo ""
fi

# Set up the tunnel
echo "Establishing SSH tunnel..."
sudo ssh -i ~/.ssh/dev-machine.pem \
    -L 8443:192.168.49.2:8443 \
    -L 80:192.168.49.2:30268 \
    ec2-user@$(cloudkube ip) 