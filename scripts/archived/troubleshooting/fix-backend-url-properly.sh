#!/bin/bash
# Properly fix the backend URL in Traefik config
# Run this on rigel

set -euo pipefail

VEGA_IP=$(getent hosts vega.tailb821ac.ts.net | awk '{print $1}')

if [[ -z "${VEGA_IP}" ]]; then
    echo "ERROR: Cannot resolve vega.tailb821ac.ts.net"
    exit 1
fi

echo "Vega IP: ${VEGA_IP}"
echo ""

# Show the current service-aispector section
echo "Current service-aispector configuration:"
grep -A 10 "service-aispector" /opt/traefik/dynamic.yml
echo ""

# Fix the URL - handle various formats
echo "Fixing backend URL..."
# Try multiple patterns to catch different formats
sed -i "s|url:.*vega.*8000|url: \"http://${VEGA_IP}:8000\"|g" /opt/traefik/dynamic.yml
sed -i "s|url:.*100\.116\.12\.30.*8000|url: \"http://${VEGA_IP}:8000\"|g" /opt/traefik/dynamic.yml
sed -i "s|\"http://vega[^\"]*:8000\"|\"http://${VEGA_IP}:8000\"|g" /opt/traefik/dynamic.yml

# If the URL line is missing, add it
if ! grep -q "url:" /opt/traefik/dynamic.yml | grep -A 5 "service-aispector"; then
    echo "URL line missing, adding it..."
    # Find the servers: line and add url after it
    sed -i "/service-aispector:/,/servers:/{ /servers:/a\          - url: \"http://${VEGA_IP}:8000\"
}" /opt/traefik/dynamic.yml
fi

echo ""
echo "Updated configuration:"
grep -A 10 "service-aispector" /opt/traefik/dynamic.yml
echo ""

# Restart Traefik
echo "Restarting Traefik..."
cd /opt/traefik && docker compose restart traefik
sleep 5

# Test
echo ""
echo "Testing..."
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health 2>&1 || echo "000")
RESPONSE=$(curl -s -k --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health 2>&1 || echo "FAILED")

if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "\033[0;32m✓ SUCCESS! HTTP ${HTTP_CODE}\033[0m"
    echo "Response: ${RESPONSE}"
elif [[ "${HTTP_CODE}" == "404" ]]; then
    echo -e "\033[0;31m✗ 404 - Route not found\033[0m"
    echo "Response: ${RESPONSE}"
    echo ""
    echo "Checking Traefik API for routes..."
    docker exec traefik wget -qO- http://localhost:8080/api/http/routers 2>/dev/null | python3 -m json.tool | grep -i aispector || echo "Route not found in API"
elif [[ "${HTTP_CODE}" == "503" ]]; then
    echo -e "\033[0;31m✗ 503 - Backend unreachable\033[0m"
    echo "Response: ${RESPONSE}"
else
    echo -e "\033[0;33m⚠ HTTP ${HTTP_CODE}\033[0m"
    echo "Response: ${RESPONSE:0:200}"
fi
