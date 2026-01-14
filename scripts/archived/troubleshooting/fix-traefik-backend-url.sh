#!/bin/bash
# Quick fix for Traefik backend URL trailing dot issue and DNS resolution
# Run this on rigel

set -euo pipefail

echo "============================================================================"
echo "Fixing Traefik Backend URL and DNS Resolution"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Fix trailing dot in dynamic.yml
echo "1. Fixing trailing dot in Traefik configuration..."
if [[ -f /opt/traefik/dynamic.yml ]]; then
    # Remove trailing dots before colons in backend URLs
    sed -i 's/\([^:]\)\(\.\)\(:\)/\1\3/g' /opt/traefik/dynamic.yml
    sed -i 's/\(tailb821ac\.ts\.net\)\(\.\)\(:\)/\1\3/g' /opt/traefik/dynamic.yml
    echo -e "${GREEN}✓${NC} Fixed trailing dots in dynamic.yml"
    
    # Show the fixed backend URL
    echo "  Backend URL:"
    grep -A 2 "service-aispector" /opt/traefik/dynamic.yml | grep "url:" || echo "  (not found)"
else
    echo -e "${RED}✗${NC} /opt/traefik/dynamic.yml not found"
    exit 1
fi
echo ""

# 2. Configure Docker to use CoreDNS (127.0.0.1) for DNS
echo "2. Configuring Docker DNS to use CoreDNS..."
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"

# Check if daemon.json exists
if [[ -f "${DOCKER_DAEMON_JSON}" ]]; then
    # Read existing config
    EXISTING_CONFIG=$(cat "${DOCKER_DAEMON_JSON}" 2>/dev/null || echo "{}")
else
    EXISTING_CONFIG="{}"
fi

# Update DNS configuration
# Use python to properly merge JSON
python3 << EOF
import json
import sys

try:
    config = json.loads('''${EXISTING_CONFIG}''')
except:
    config = {}

# Set DNS to use CoreDNS (127.0.0.1) and fallback to 8.8.8.8
config['dns'] = ['127.0.0.1', '8.8.8.8']

# Write updated config
with open('${DOCKER_DAEMON_JSON}', 'w') as f:
    json.dump(config, f, indent=2)

print("DNS configured: 127.0.0.1 (CoreDNS), 8.8.8.8 (fallback)")
EOF

echo -e "${GREEN}✓${NC} Docker DNS configured"
echo ""

# 3. Restart Docker to apply DNS changes
echo "3. Restarting Docker to apply DNS configuration..."
sudo systemctl restart docker
sleep 5
echo -e "${GREEN}✓${NC} Docker restarted"
echo ""

# 4. Restart Traefik to pick up config changes
echo "4. Restarting Traefik..."
cd /opt/traefik && docker compose restart traefik
sleep 5
echo -e "${GREEN}✓${NC} Traefik restarted"
echo ""

# 5. Test DNS resolution from Traefik container
echo "5. Testing DNS resolution from Traefik container..."
echo -n "  Testing vega.tailb821ac.ts.net resolution... "
if docker exec traefik getent hosts vega.tailb821ac.ts.net &>/dev/null; then
    echo -e "${GREEN}✓${NC} Resolves"
    docker exec traefik getent hosts vega.tailb821ac.ts.net
else
    echo -e "${RED}✗${NC} Does not resolve"
    echo "  Trying IP address test..."
    VEGA_IP=$(getent hosts vega.tailb821ac.ts.net | awk '{print $1}' || echo "")
    if [[ -n "${VEGA_IP}" ]]; then
        echo "  vega.tailb821ac.ts.net resolves to: ${VEGA_IP}"
        echo "  Consider using IP address directly in backend URL"
    fi
fi
echo ""

# 6. Test backend connectivity from Traefik
echo "6. Testing backend connectivity from Traefik container..."
echo -n "  Testing http://vega.tailb821ac.ts.net:8000/health... "
if docker exec traefik wget -qO- --timeout=5 http://vega.tailb821ac.ts.net:8000/health &>/dev/null; then
    echo -e "${GREEN}✓${NC} Reachable"
    docker exec traefik wget -qO- --timeout=5 http://vega.tailb821ac.ts.net:8000/health
else
    echo -e "${RED}✗${NC} Not reachable"
    echo "  Trying with IP address..."
    VEGA_IP=$(getent hosts vega.tailb821ac.ts.net | awk '{print $1}' || echo "")
    if [[ -n "${VEGA_IP}" ]]; then
        if docker exec traefik wget -qO- --timeout=5 http://${VEGA_IP}:8000/health &>/dev/null; then
            echo -e "${GREEN}✓${NC} Reachable via IP: ${VEGA_IP}"
            echo "  Consider using IP address in backend URL if FQDN doesn't work"
        else
            echo -e "${RED}✗${NC} Not reachable via IP either"
        fi
    fi
fi
echo ""

# 7. Test Traefik routing
echo "7. Testing Traefik routing..."
echo -n "  Testing https://aispector.exnada.com/health... "
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health 2>&1 || echo "000")
if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓${NC} Working! (HTTP ${HTTP_CODE})"
    RESPONSE=$(curl -s -k --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health)
    echo "  Response: ${RESPONSE:0:100}"
elif [[ "${HTTP_CODE}" == "503" ]]; then
    echo -e "${RED}✗${NC} Still getting 503 - Backend unreachable"
    echo "  Checking Traefik logs..."
    docker logs traefik 2>&1 | tail -20 | grep -i "backend\|503\|error" || echo "  No relevant logs"
elif [[ "${HTTP_CODE}" == "404" ]]; then
    echo -e "${RED}✗${NC} 404 - Route not found"
else
    echo -e "${YELLOW}⚠${NC} HTTP ${HTTP_CODE}"
fi
echo ""

# Summary
echo "============================================================================"
if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓ Reverse proxy is working!${NC}"
    echo ""
    echo "Final test:"
    curl -s -k -H "Host: aispector.exnada.com" https://localhost/health
else
    echo -e "${RED}✗ Reverse proxy still has issues${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Check Traefik logs: docker logs traefik | tail -50"
    echo "2. Verify backend URL in config: grep -A 2 'service-aispector' /opt/traefik/dynamic.yml"
    echo "3. Test backend directly: curl http://vega.tailb821ac.ts.net:8000/health"
    echo "4. If DNS doesn't work, consider using IP address in backend URL"
fi
echo "============================================================================"
