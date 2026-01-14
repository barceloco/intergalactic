#!/bin/bash
# Check Traefik routing and backend connectivity
# Run this on rigel to diagnose 404 errors

set -euo pipefail

echo "============================================================================"
echo "Traefik Routing Diagnostic"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. Traefik Container Status"
echo "----------------------------------------"
if docker ps | grep -q traefik; then
    echo -e "${GREEN}✓${NC} Traefik is running"
    docker ps | grep traefik
else
    echo -e "${RED}✗${NC} Traefik is not running"
    exit 1
fi
echo ""

echo "2. Traefik Configuration Files"
echo "----------------------------------------"
for file in "/opt/traefik/traefik.yml" "/opt/traefik/dynamic.yml"; do
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓${NC} $file exists"
        echo "  Size: $(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null) bytes"
    else
        echo -e "${RED}✗${NC} $file missing"
    fi
done
echo ""

echo "3. Traefik Dynamic Configuration (Routes)"
echo "----------------------------------------"
if [[ -f "/opt/traefik/dynamic.yml" ]]; then
    echo "Routes configured:"
    grep -A 5 "router-" /opt/traefik/dynamic.yml | grep -E "(router-|rule:|service:)" | head -20 || echo "No routes found"
else
    echo -e "${RED}✗${NC} dynamic.yml not found"
fi
echo ""

echo "4. Backend Service Connectivity"
echo "----------------------------------------"
echo "Testing backend services from rigel:"
echo ""

# Test vega:8000
echo -n "Testing vega:8000/health... "
if curl -s --max-time 5 http://vega:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Reachable"
    curl -s --max-time 5 http://vega:8000/health | head -1
else
    echo -e "${RED}✗${NC} Not reachable"
    echo "  Trying via Tailscale FQDN..."
    if curl -s --max-time 5 http://vega.tailb821ac.ts.net:8000/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Reachable via Tailscale FQDN"
    else
        echo -e "${RED}✗${NC} Not reachable via Tailscale FQDN either"
    fi
fi
echo ""

# Test rigel:8000
echo -n "Testing rigel:8000/health... "
if curl -s --max-time 5 http://rigel:8000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Reachable"
    curl -s --max-time 5 http://rigel:8000/health | head -1
else
    echo -e "${RED}✗${NC} Not reachable"
    echo "  Trying via Tailscale FQDN..."
    if curl -s --max-time 5 http://rigel.tailb821ac.ts.net:8000/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Reachable via Tailscale FQDN"
    else
        echo -e "${RED}✗${NC} Not reachable via Tailscale FQDN either"
    fi
fi
echo ""

# Test mpnas:5000
echo -n "Testing mpnas:5000... "
if curl -s --max-time 5 http://mpnas:5000 >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Reachable"
    curl -s --max-time 5 http://mpnas:5000 | head -1
else
    echo -e "${RED}✗${NC} Not reachable"
    echo "  Trying via Tailscale FQDN..."
    if curl -s --max-time 5 http://mpnas.tailb821ac.ts.net:5000 >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Reachable via Tailscale FQDN"
    else
        echo -e "${RED}✗${NC} Not reachable via Tailscale FQDN either"
    fi
fi
echo ""

echo "5. Traefik Logs (last 50 lines, errors only)"
echo "----------------------------------------"
docker logs traefik 2>&1 | tail -50 | grep -i "error\|warn\|404\|router" || echo "No recent errors"
echo ""

echo "6. Testing Traefik Routes Directly"
echo "----------------------------------------"
echo "Testing via Traefik (localhost:443):"
echo ""

for host in "aispector.exnada.com" "dev.exnada.com" "mpnas.exnada.com"; do
    echo -n "Testing ${host}... "
    RESPONSE=$(curl -s -k --max-time 5 -H "Host: ${host}" https://localhost/health 2>&1 || echo "FAILED")
    if echo "${RESPONSE}" | grep -q "404\|not found"; then
        echo -e "${RED}✗${NC} 404 Not Found"
    elif echo "${RESPONSE}" | grep -q "health\|ok\|200"; then
        echo -e "${GREEN}✓${NC} Working"
    else
        echo -e "${YELLOW}⚠${NC} Unexpected response: ${RESPONSE:0:50}"
    fi
done
echo ""

echo "7. Certificate Status"
echo "----------------------------------------"
if [[ -f "/opt/traefik/certs/exnada.com.crt" ]]; then
    echo -e "${GREEN}✓${NC} Certificate exists"
    openssl x509 -in /opt/traefik/certs/exnada.com.crt -noout -subject -dates 2>/dev/null || echo "Could not read certificate"
else
    echo -e "${RED}✗${NC} Certificate missing"
fi
echo ""

echo "============================================================================"
echo "Diagnostic complete"
echo "============================================================================"
