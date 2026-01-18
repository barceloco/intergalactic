#!/bin/bash
# Emergency check for vega firewall - run this on vega
# This checks if the firewall is blocking localhost connections

set -euo pipefail

echo "============================================================================"
echo "Emergency Firewall Check for vega"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. Check if service is still running"
echo "----------------------------------------"
if ss -tlnp | grep :8001 >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Service is listening on port 8001"
    ss -tlnp | grep :8001
else
    echo -e "${RED}✗${NC} Service is NOT listening on port 8001"
    echo "  The service may have stopped!"
fi
echo ""

echo "2. Check current firewall rules"
echo "----------------------------------------"
if sudo nft list ruleset 2>/dev/null | grep -A 5 "chain input" | head -20; then
    echo ""
    echo "Checking for loopback rule:"
    if sudo nft list ruleset 2>/dev/null | grep -q "iif lo accept"; then
        echo -e "${GREEN}✓${NC} Loopback accept rule exists"
    else
        echo -e "${RED}✗${NC} Loopback accept rule MISSING!"
    fi
else
    echo "Could not list firewall rules"
fi
echo ""

echo "3. Test localhost connectivity"
echo "----------------------------------------"
echo -n "Testing 127.0.0.1:8001... "
if curl -s --max-time 2 http://127.0.0.1:8001/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Works"
else
    echo -e "${RED}✗${NC} Failed"
fi
echo ""

echo "4. Check firewall status"
echo "----------------------------------------"
if systemctl is-active --quiet nftables; then
    echo -e "${GREEN}✓${NC} nftables is active"
else
    echo -e "${YELLOW}⚠${NC} nftables is not active"
fi
echo ""

echo "============================================================================"
echo "Quick Fix Options"
echo "============================================================================"
echo "If localhost is blocked, try:"
echo "  1. Restart the service: sudo systemctl restart <service-name>"
echo "  2. Temporarily disable firewall: sudo systemctl stop nftables"
echo "  3. Check firewall rules: sudo nft list ruleset | grep -A 10 'chain input'"
echo "============================================================================"
