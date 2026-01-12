#!/bin/bash
# Final test for aispector.exnada.com
# Tests from outside via HTTPS

set -euo pipefail

echo "============================================================================"
echo "Final Test: aispector.exnada.com"
echo "============================================================================"
echo ""

# Test HTTPS endpoint
echo "Testing: https://aispector.exnada.com/health"
echo "----------------------------------------"

HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 https://aispector.exnada.com/health 2>&1 || echo "000")
RESPONSE=$(curl -s -k --max-time 10 https://aispector.exnada.com/health 2>&1 || echo "FAILED")

if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "\033[0;32m✓ SUCCESS! HTTP ${HTTP_CODE}\033[0m"
    echo ""
    echo "Response:"
    echo "${RESPONSE}"
    echo ""
    echo -e "\033[0;32mReverse proxy is working correctly!\033[0m"
    exit 0
else
    echo -e "\033[0;31m✗ FAILED - HTTP ${HTTP_CODE}\033[0m"
    echo ""
    echo "Response:"
    echo "${RESPONSE:0:500}"
    echo ""
    echo "This test requires:"
    echo "1. DNS resolution (aispector.exnada.com resolves to rigel's IP)"
    echo "2. Tailscale connectivity"
    echo "3. Traefik routing configured correctly"
    exit 1
fi
