#!/bin/bash
# Diagnose why vega:8001 is not accessible from other hosts
# Run this on vega

set -euo pipefail

echo "============================================================================"
echo "Diagnosing vega:8001 Connectivity Issue"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. Checking what's listening on port 8001"
echo "----------------------------------------"
if command -v ss >/dev/null 2>&1; then
    echo "Using 'ss' command:"
    ss -tlnp | grep :8001 || echo -e "${RED}✗${NC} Nothing listening on port 8001"
else
    echo "Using 'netstat' command:"
    netstat -tlnp 2>/dev/null | grep :8001 || echo -e "${RED}✗${NC} Nothing listening on port 8001"
fi
echo ""

echo "2. Testing localhost connectivity"
echo "----------------------------------------"
echo -n "Testing localhost:8001/health... "
if curl -s --max-time 5 http://localhost:8001/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Reachable"
    curl -s --max-time 5 http://localhost:8001/health | head -1
else
    echo -e "${RED}✗${NC} Not reachable"
fi
echo ""

echo -n "Testing 127.0.0.1:8001/health... "
if curl -s --max-time 5 http://127.0.0.1:8001/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Reachable"
else
    echo -e "${RED}✗${NC} Not reachable"
fi
echo ""

echo "3. DNS Resolution Check"
echo "----------------------------------------"
echo "What does 'vega' resolve to on this host?"
getent hosts vega 2>/dev/null || echo "Could not resolve 'vega'"
echo ""

VEGA_IP=$(tailscale ip -4 2>/dev/null || echo "")
if [[ -n "${VEGA_IP}" ]]; then
    echo "Vega Tailscale IP: ${VEGA_IP}"
    echo -n "Testing ${VEGA_IP}:8001/health... "
    if curl -s --max-time 5 http://${VEGA_IP}:8001/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Reachable via Tailscale IP"
    else
        echo -e "${RED}✗${NC} Not reachable via Tailscale IP"
        echo -e "${YELLOW}⚠${NC} Service may not be binding to Tailscale interface!"
    fi
else
    echo -e "${RED}✗${NC} Could not get Tailscale IP"
fi
echo ""

echo "Testing via Tailscale FQDN..."
VEGA_FQDN=$(tailscale status --json 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print([p['DNSName'] for p in data.get('Peer', {}).values() if p.get('Online') and 'vega' in p.get('DNSName', '').lower()][0] if data.get('Peer') else '')" 2>/dev/null || echo "")
if [[ -n "${VEGA_FQDN}" ]]; then
    echo "Vega Tailscale FQDN: ${VEGA_FQDN}"
    echo -n "Testing ${VEGA_FQDN}:8001/health... "
    if curl -s --max-time 5 http://${VEGA_FQDN}:8001/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Reachable via Tailscale FQDN"
    else
        echo -e "${RED}✗${NC} Not reachable via Tailscale FQDN"
    fi
else
    echo "Could not determine Tailscale FQDN"
fi
echo ""

echo "4. Checking Docker containers"
echo "----------------------------------------"
echo "Containers listening on port 8001:"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -E "8001|NAMES" || echo "No containers found with port 8001"
echo ""

echo "All running containers:"
docker ps --format "table {{.Names}}\t{{.Ports}}" | head -10
echo ""

echo "5. Checking firewall status"
echo "----------------------------------------"
if systemctl is-active --quiet nftables; then
    echo -e "${GREEN}✓${NC} nftables is active"
    echo "Current firewall rules for port 8001:"
    sudo nft list ruleset | grep -E "8001|tailscale0" || echo "No specific rules for 8001"
else
    echo -e "${YELLOW}⚠${NC} nftables is not active"
fi
echo ""

echo "6. Checking if service is bound to localhost only"
echo "----------------------------------------"
if command -v ss >/dev/null 2>&1; then
    LISTEN_INFO=$(ss -tlnp | grep :8001 || echo "")
    if [[ -n "${LISTEN_INFO}" ]]; then
        if echo "${LISTEN_INFO}" | grep -q "127.0.0.1:8001"; then
            echo -e "${RED}✗${NC} Service is bound to 127.0.0.1:8001 (localhost only)"
            echo "  This is why it's not accessible from other hosts!"
            echo ""
            echo "  Solution: Configure the service to bind to 0.0.0.0:8001"
            echo "  - For Docker: Use '0.0.0.0:8001' in port mapping or bind address"
            echo "  - For systemd: Set bind address to '0.0.0.0' or '*'"
            echo "  - For Python: Use app.run(host='0.0.0.0', port=8001)"
            echo "  - For Node.js: Use app.listen(8001, '0.0.0.0')"
        elif echo "${LISTEN_INFO}" | grep -q "0.0.0.0:8001\|:::8001"; then
            echo -e "${GREEN}✓${NC} Service is bound to 0.0.0.0:8001 (all interfaces)"
            echo "  If it's still not accessible, check firewall rules"
        else
            echo -e "${YELLOW}⚠${NC} Could not determine bind address from:"
            echo "  ${LISTEN_INFO}"
        fi
    else
        echo -e "${RED}✗${NC} Nothing listening on port 8001"
    fi
else
    echo "ss command not available, using netstat:"
    netstat -tlnp 2>/dev/null | grep :8001 || echo "Nothing listening on port 8001"
fi
echo ""

echo "============================================================================"
echo "Summary"
echo "============================================================================"
echo "If the service is bound to 127.0.0.1:8001, you need to:"
echo "  1. Find the service configuration (Docker compose, systemd service, etc.)"
echo "  2. Change the bind address from '127.0.0.1' or 'localhost' to '0.0.0.0'"
echo "  3. Restart the service"
echo ""
echo "If the service is bound to 0.0.0.0:8001 but still not accessible:"
echo "  1. Check firewall rules: sudo nft list ruleset | grep 8001"
echo "  2. Verify Tailscale connectivity: tailscale ping rigel"
echo "  3. Test from rigel: curl http://vega:8001/health"
echo "============================================================================"
