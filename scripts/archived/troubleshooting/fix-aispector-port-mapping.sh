#!/bin/bash
# Check and fix port mapping for aispector-api container
# Run this on rigel

set -euo pipefail

echo "============================================================================"
echo "Checking aispector-api Port Mapping"
echo "============================================================================"
echo ""

# Check if container exists
if ! docker ps --format "{{.Names}}" | grep -q "aispector-api"; then
    echo "ERROR: aispector-api container not found"
    exit 1
fi

echo "1. Current Container Status"
echo "----------------------------------------"
docker ps --filter "name=aispector-api" --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"
echo ""

echo "2. Current Port Bindings"
echo "----------------------------------------"
PORT_BINDINGS=$(docker inspect aispector-api --format '{{json .HostConfig.PortBindings}}' 2>/dev/null)
if [[ "${PORT_BINDINGS}" == "null" ]] || [[ -z "${PORT_BINDINGS}" ]] || [[ "${PORT_BINDINGS}" == "{}" ]]; then
    echo -e "\033[0;31m✗ No port bindings found!\033[0m"
    echo "  The container is not exposing port 8000 to the host."
    echo ""
    echo "3. Solution"
    echo "----------------------------------------"
    echo "You need to add a port mapping to your docker-compose.yml or docker run command:"
    echo ""
    echo "For docker-compose.yml:"
    echo "  services:"
    echo "    api:"
    echo "      ports:"
    echo "        - \"8000:8000\""
    echo ""
    echo "For docker run:"
    echo "  docker run -p 8000:8000 ..."
    echo ""
    echo "After adding the port mapping, restart the container:"
    echo "  docker compose restart api  # or docker restart aispector-api"
    echo ""
    echo "============================================================================"
    echo "Note: Since Traefik uses host networking, it can only reach containers"
    echo "that expose ports to the host (localhost:8000)."
    echo "============================================================================"
    exit 1
else
    echo -e "\033[0;32m✓ Port bindings found:\033[0m"
    echo "${PORT_BINDINGS}" | python3 -m json.tool 2>/dev/null || echo "${PORT_BINDINGS}"
    echo ""
    
    # Check if port 8000 is mapped
    if echo "${PORT_BINDINGS}" | grep -q "8000"; then
        echo -e "\033[0;32m✓ Port 8000 is mapped\033[0m"
    else
        echo -e "\033[0;31m✗ Port 8000 is NOT mapped\033[0m"
        echo "  You need to add port mapping for 8000:8000"
    fi
fi
echo ""

echo "4. Testing Container Accessibility"
echo "----------------------------------------"
echo "Testing from inside the container's network..."
CONTAINER_IP=$(docker inspect aispector-api --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1)
if [[ -n "${CONTAINER_IP}" ]]; then
    echo "Container IP: ${CONTAINER_IP}"
    if curl -s --max-time 5 http://${CONTAINER_IP}:8000/health >/dev/null 2>&1; then
        echo -e "\033[0;32m✓ Container is reachable at ${CONTAINER_IP}:8000\033[0m"
        echo "  But Traefik can't reach it because it's not exposed to the host!"
    else
        echo -e "\033[0;31m✗ Container not reachable at ${CONTAINER_IP}:8000\033[0m"
    fi
else
    echo "Could not determine container IP"
fi
echo ""

echo "Testing from host (localhost:8000)..."
if curl -s --max-time 5 http://localhost:8000/health >/dev/null 2>&1; then
    echo -e "\033[0;32m✓ localhost:8000 is reachable\033[0m"
    curl -s --max-time 5 http://localhost:8000/health | head -1
else
    echo -e "\033[0;31m✗ localhost:8000 is NOT reachable\033[0m"
    echo "  This confirms the port is not exposed to the host."
fi
echo ""
