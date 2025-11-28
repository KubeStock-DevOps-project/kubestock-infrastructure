#!/bin/bash
# start-nginx-proxy.sh
# Starts the nginx proxy container that proxies API server requests to the control plane
# The proxy binds to 127.0.0.1:6443 and forwards to the control plane

set -e

CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-10.0.10.21}"
NGINX_IMAGE="docker.io/library/nginx:1.28.0-alpine"

echo "Starting nginx-proxy..."

# Check if container already exists
if nerdctl ps -a --format '{{.Names}}' | grep -q '^nginx-proxy$'; then
    # Check if running
    if nerdctl ps --format '{{.Names}}' | grep -q '^nginx-proxy$'; then
        echo "nginx-proxy is already running"
    else
        echo "Starting existing nginx-proxy container..."
        nerdctl start nginx-proxy
    fi
else
    # Create and start new container
    nerdctl run -d \
        --name nginx-proxy \
        --network host \
        --restart always \
        -v /etc/nginx:/etc/nginx:ro \
        "${NGINX_IMAGE}"
fi

# Wait for nginx to be ready
MAX_ATTEMPTS=30
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    if curl -sk https://127.0.0.1:6443/version > /dev/null 2>&1; then
        echo "nginx-proxy is ready"
        exit 0
    fi
    echo "Waiting for nginx-proxy... ($ATTEMPT/$MAX_ATTEMPTS)"
    sleep 5
done

echo "ERROR: nginx-proxy failed to start after $MAX_ATTEMPTS attempts"
exit 1
