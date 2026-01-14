#!/bin/bash
# Fix YAML syntax error in Traefik dynamic.yml
# Run this on rigel

set -euo pipefail

echo "Fixing YAML syntax error (double quotes)..."
sed -i 's/8000""/8000"/g' /opt/traefik/dynamic.yml

echo "Fixed. Verifying..."
grep -n "url:" /opt/traefik/dynamic.yml

echo ""
echo "Restarting Traefik..."
cd /opt/traefik && docker compose restart traefik
sleep 5

echo ""
echo "Testing..."
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health 2>&1 || echo "000")
RESPONSE=$(curl -s -k --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health 2>&1 || echo "FAILED")

if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "\033[0;32m✓ SUCCESS! HTTP ${HTTP_CODE}\033[0m"
    echo "Response: ${RESPONSE}"
else
    echo -e "\033[0;31m✗ HTTP ${HTTP_CODE}\033[0m"
    echo "Response: ${RESPONSE:0:200}"
fi
