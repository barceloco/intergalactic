#!/bin/bash
# Check DNS resolution and connectivity for vega:8001
# Run this on both vega and rigel to compare

set -euo pipefail

echo "============================================================================"
echo "Checking vega:8001 DNS Resolution and Connectivity"
echo "Host: $(hostname)"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. DNS Resolution"
echo "----------------------------------------"
echo "What does 'vega' resolve to?"
getent hosts vega 2>/dev/null | head -5 || echo -e "${RED}✗${NC} Could not resolve 'vega'"
echo ""

echo "2. Tailscale Status"
echo "----------------------------------------"
if command -v tailscale >/dev/null 2>&1; then
    echo "Vega's Tailscale IP:"
    tailscale status 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s+vega\s" || echo "Vega not found in tailscale status"
    echo ""
    
    echo "Vega's Tailscale FQDN (if available):"
    tailscale status --json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for peer in data.get('Peer', {}).values():
        if 'vega' in peer.get('DNSName', '').lower():
            print(f\"  {peer.get('DNSName')} - {peer.get('Online', False)}\")
            break
except:
    pass
" 2>/dev/null || echo "Could not determine FQDN"
else
    echo -e "${YELLOW}⚠${NC} tailscale command not available"
fi
echo ""

echo "3. Connectivity Tests"
echo "----------------------------------------"
echo -n "Testing vega:8001/health... "
if curl -s --max-time 5 http://vega:8001/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Reachable"
    RESPONSE=$(curl -s --max-time 5 http://vega:8001/health)
    echo "  Response: ${RESPONSE}"
else
    echo -e "${RED}✗${NC} Not reachable"
fi
echo ""

# Get vega's IP
VEGA_IP=$(getent hosts vega 2>/dev/null | awk '{print $1}' | head -1)
if [[ -n "${VEGA_IP}" ]]; then
    echo "Testing ${VEGA_IP}:8001/health (resolved IP)... "
    if curl -s --max-time 5 http://${VEGA_IP}:8001/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Reachable via IP"
    else
        echo -e "${RED}✗${NC} Not reachable via IP"
    fi
    echo ""
fi

# Try Tailscale IP
VEGA_TS_IP=$(tailscale status 2>/dev/null | grep -E "^\s*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s+vega\s" | awk '{print $1}' | head -1)
if [[ -n "${VEGA_TS_IP}" ]]; then
    echo "Testing ${VEGA_TS_IP}:8001/health (Tailscale IP)... "
    if curl -s --max-time 5 http://${VEGA_TS_IP}:8001/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Reachable via Tailscale IP"
    else
        echo -e "${RED}✗${NC} Not reachable via Tailscale IP"
        echo -e "${YELLOW}⚠${NC} This suggests the service is not accessible on the Tailscale interface"
    fi
    echo ""
fi

echo "4. Network Interface Check (on vega only)"
echo "----------------------------------------"
if [[ "$(hostname)" == "vega" ]]; then
    echo "What's listening on port 8001?"
    if command -v ss >/dev/null 2>&1; then
        ss -tlnp | grep :8001 || echo "Nothing listening on port 8001"
    else
        netstat -tlnp 2>/dev/null | grep :8001 || echo "Nothing listening on port 8001"
    fi
    echo ""
    
    echo "Network interfaces:"
    ip addr show | grep -E "^[0-9]+:|inet " | head -10
else
    echo "Run this on vega to see interface details"
fi
echo ""

echo "============================================================================"
echo "Diagnosis"
echo "============================================================================"
if [[ -n "${VEGA_TS_IP:-}" ]] && curl -s --max-time 2 http://${VEGA_TS_IP}:8001/health >/dev/null 2>&1; then
    echo -e "${GREEN}Service is accessible via Tailscale IP${NC}"
    echo "If DNS on rigel resolves 'vega' to a different IP, that's the issue."
elif [[ -n "${VEGA_TS_IP:-}" ]]; then
    echo -e "${RED}Service is NOT accessible via Tailscale IP${NC}"
    echo "The service may be bound to localhost only or a different interface."
    echo "Check what's listening on port 8001 on vega."
else
    echo "Could not determine Tailscale IP for diagnosis"
fi
echo "============================================================================"
