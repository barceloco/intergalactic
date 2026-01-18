#!/bin/bash
# Test vega:8001 connectivity from rigel
# Run this on rigel

set -euo pipefail

echo "============================================================================"
echo "Testing vega:8001 Connectivity from rigel"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. DNS Resolution"
echo "----------------------------------------"
echo "What does 'vega' resolve to on rigel?"
VEGA_RESOLVED=$(getent hosts vega 2>/dev/null | awk '{print $1}' | head -1)
if [[ -n "${VEGA_RESOLVED}" ]]; then
    echo "  vega → ${VEGA_RESOLVED}"
    
    # Check if it's a Tailscale IP
    if [[ "${VEGA_RESOLVED}" =~ ^100\. ]]; then
        echo -e "  ${GREEN}✓${NC} Resolves to Tailscale IP (100.x.x.x)"
    else
        echo -e "  ${YELLOW}⚠${NC} Resolves to ${VEGA_RESOLVED} (not a Tailscale IP)"
    fi
else
    echo -e "  ${RED}✗${NC} Could not resolve 'vega'"
    exit 1
fi
echo ""

echo "2. Tailscale Connectivity"
echo "----------------------------------------"
echo "Checking Tailscale status for vega:"
tailscale status 2>/dev/null | grep -E "vega|${VEGA_RESOLVED}" || echo "Vega not found in tailscale status"
echo ""

echo -n "Testing Tailscale ping to vega... "
if tailscale ping -c 1 vega >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Tailscale connectivity OK"
else
    echo -e "${RED}✗${NC} Tailscale ping failed"
fi
echo ""

echo "3. Direct IP Connectivity"
echo "----------------------------------------"
echo -n "Testing ${VEGA_RESOLVED}:8001/health (direct IP)... "
if curl -s --max-time 5 http://${VEGA_RESOLVED}:8001/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Reachable via IP"
    RESPONSE=$(curl -s --max-time 5 http://${VEGA_RESOLVED}:8001/health)
    echo "  Response: ${RESPONSE}"
else
    echo -e "${RED}✗${NC} Not reachable via IP"
    echo "  This suggests a firewall or routing issue"
fi
echo ""

echo "4. Hostname Connectivity"
echo "----------------------------------------"
echo -n "Testing vega:8001/health (hostname)... "
if curl -s --max-time 5 http://vega:8001/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Reachable via hostname"
    RESPONSE=$(curl -s --max-time 5 http://vega:8001/health)
    echo "  Response: ${RESPONSE}"
else
    echo -e "${RED}✗${NC} Not reachable via hostname"
fi
echo ""

echo "5. Tailscale FQDN Connectivity"
echo "----------------------------------------"
VEGA_FQDN=$(tailscale status --json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for peer in data.get('Peer', {}).values():
        dns_name = peer.get('DNSName', '')
        if 'vega' in dns_name.lower():
            print(dns_name)
            break
except:
    pass
" 2>/dev/null || echo "")

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

echo "6. Network Trace"
echo "----------------------------------------"
echo "Tracing route to vega:8001..."
if command -v traceroute >/dev/null 2>&1; then
    traceroute -n -m 5 ${VEGA_RESOLVED} 2>&1 | head -10 || echo "Traceroute failed"
elif command -v tracepath >/dev/null 2>&1; then
    tracepath -n ${VEGA_RESOLVED} 2>&1 | head -10 || echo "Tracepath failed"
else
    echo "No traceroute/tracepath available"
fi
echo ""

echo "============================================================================"
echo "Diagnosis"
echo "============================================================================"
if curl -s --max-time 2 http://${VEGA_RESOLVED}:8001/health >/dev/null 2>&1; then
    echo -e "${GREEN}Service is reachable via IP${NC}"
    echo "If hostname doesn't work, it's a DNS resolution issue."
    echo "Try using the IP directly or fix DNS resolution."
elif tailscale ping -c 1 vega >/dev/null 2>&1; then
    echo -e "${RED}Service is NOT reachable despite Tailscale connectivity${NC}"
    echo "This suggests a firewall issue on vega."
    echo "Check vega's firewall rules for port 8001."
else
    echo -e "${RED}Tailscale connectivity issue${NC}"
    echo "Check Tailscale status on both hosts."
fi
echo "============================================================================"
