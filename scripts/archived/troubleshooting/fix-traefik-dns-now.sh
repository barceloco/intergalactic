#!/bin/bash
# Immediate fix for Traefik backend - use IP address
# Run this on rigel

set -euo pipefail

echo "============================================================================"
echo "Quick Fix: Using IP Address for Backend"
echo "============================================================================"
echo ""

# Get vega's IP
VEGA_IP=$(getent hosts vega.tailb821ac.ts.net | awk '{print $1}')

if [[ -z "${VEGA_IP}" ]]; then
    echo "ERROR: Cannot resolve vega.tailb821ac.ts.net"
    exit 1
fi

echo "Vega IP: ${VEGA_IP}"
echo ""

# Fix the backend URL to use IP address
echo "Updating Traefik configuration to use IP address..."
sed -i "s|url: \"http://vega.*:8000\"|url: \"http://${VEGA_IP}:8000\"|g" /opt/traefik/dynamic.yml

echo "Updated backend URL:"
grep -A 2 "service-aispector" /opt/traefik/dynamic.yml | grep "url:"

# Restart Traefik
echo ""
echo "Restarting Traefik..."
cd /opt/traefik && docker compose restart traefik
sleep 5

# Test
echo ""
echo "Testing..."
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health 2>&1 || echo "000")

if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "\033[0;32m✓ SUCCESS! Reverse proxy is working!\033[0m"
    echo ""
    curl -s -k -H "Host: aispector.exnada.com" https://localhost/health
else
    echo -e "\033[0;31m✗ Still failing (HTTP ${HTTP_CODE})\033[0m"
    echo "Check logs: docker logs traefik | tail -20"
fi
