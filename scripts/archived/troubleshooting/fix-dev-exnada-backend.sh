#!/bin/bash
# Quick fix for dev.exnada.com - use localhost instead of Tailscale FQDN
# Run this on rigel

set -euo pipefail

echo "============================================================================"
echo "Fixing dev.exnada.com Backend URL"
echo "============================================================================"
echo ""

# Check if dynamic.yml exists
if [[ ! -f "/opt/traefik/dynamic.yml" ]]; then
    echo "ERROR: /opt/traefik/dynamic.yml not found"
    exit 1
fi

# Show current configuration
echo "Current service-dev configuration:"
grep -A 10 "service-dev" /opt/traefik/dynamic.yml | head -15 || echo "Service not found"
echo ""

# Fix the URL to use localhost
echo "Updating backend URL to use localhost:8000..."
sed -i 's|url: "http://rigel[^"]*:8000"|url: "http://localhost:8000"|g' /opt/traefik/dynamic.yml
sed -i 's|url: "http://rigel\.tailb821ac\.ts\.net:8000"|url: "http://localhost:8000"|g' /opt/traefik/dynamic.yml

echo ""
echo "Updated configuration:"
grep -A 10 "service-dev" /opt/traefik/dynamic.yml | head -15
echo ""

# Restart Traefik
echo "Restarting Traefik..."
cd /opt/traefik && docker compose restart traefik
sleep 5

# Test
echo ""
echo "Testing dev.exnada.com..."
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: dev.exnada.com" https://localhost/health 2>&1 || echo "000")
RESPONSE=$(curl -s -k --max-time 10 -H "Host: dev.exnada.com" https://localhost/health 2>&1 || echo "FAILED")

if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "\033[0;32m✓ SUCCESS! HTTP ${HTTP_CODE}\033[0m"
    echo "Response: ${RESPONSE}"
    echo ""
    echo "You can now access dev.exnada.com from your browser!"
elif [[ "${HTTP_CODE}" == "404" ]]; then
    echo -e "\033[0;31m✗ Still getting 404 - Route may not be configured\033[0m"
    echo "Check Traefik logs: docker logs traefik | tail -20"
elif [[ "${HTTP_CODE}" == "502" ]] || [[ "${HTTP_CODE}" == "503" ]]; then
    echo -e "\033[0;31m✗ ${HTTP_CODE} Bad Gateway - Container may not be running on port 8000\033[0m"
    echo "Check if container is running: docker ps | grep 8000"
    echo "Check if port is listening: netstat -tuln | grep 8000"
else
    echo -e "\033[0;33m⚠ Unexpected response (HTTP ${HTTP_CODE})\033[0m"
    echo "Response: ${RESPONSE}"
fi
echo ""

echo "============================================================================"
echo "Note: This is a temporary fix. For a permanent solution, update"
echo "ansible/inventories/prod/host_vars/rigel.yml to use:"
echo "  backend: http://localhost:8000"
echo "for services on the same host."
echo "============================================================================"
