#!/bin/bash
# Verify that port 8001 is allowed in vega's firewall
# Run this on vega

set -euo pipefail

echo "============================================================================"
echo "Verifying Firewall Rules for Port 8001 on vega"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. Check current firewall rules"
echo "----------------------------------------"
echo "Looking for port 8001 in firewall rules:"
if sudo nft list ruleset 2>/dev/null | grep -E "8001|dport.*8001"; then
    echo -e "${GREEN}✓${NC} Port 8001 is in firewall rules"
else
    echo -e "${RED}✗${NC} Port 8001 is NOT in firewall rules!"
fi
echo ""

echo "2. Check firewall configuration file"
echo "----------------------------------------"
if sudo grep -q "8001" /etc/nftables.conf 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Port 8001 is in /etc/nftables.conf"
    sudo grep "8001" /etc/nftables.conf
else
    echo -e "${RED}✗${NC} Port 8001 is NOT in /etc/nftables.conf"
    echo ""
    echo "Current firewall_allow_tcp_ports rules:"
    sudo grep -A 2 "firewall_allow_tcp_ports" /etc/nftables.conf || echo "Could not find firewall_allow_tcp_ports"
fi
echo ""

echo "3. Check if firewall needs to be reloaded"
echo "----------------------------------------"
echo "Comparing /etc/nftables.conf with active rules..."
CONFIG_HAS_8001=$(sudo grep -c "8001" /etc/nftables.conf 2>/dev/null || echo "0")
ACTIVE_HAS_8001=$(sudo nft list ruleset 2>/dev/null | grep -c "8001" || echo "0")

if [[ "${CONFIG_HAS_8001}" -gt 0 ]] && [[ "${ACTIVE_HAS_8001}" -eq 0 ]]; then
    echo -e "${YELLOW}⚠${NC} Port 8001 is in config but NOT in active rules!"
    echo "  Firewall needs to be reloaded"
    echo ""
    echo "  To fix, run:"
    echo "    sudo nft -f /etc/nftables.conf"
    echo "    # or"
    echo "    sudo systemctl reload nftables"
elif [[ "${CONFIG_HAS_8001}" -eq 0 ]]; then
    echo -e "${RED}✗${NC} Port 8001 is not in configuration"
    echo "  The firewall configuration needs to be regenerated"
    echo "  Run: ./scripts/run-ansible.sh prod vega foundation --tags firewall_nftables"
else
    echo -e "${GREEN}✓${NC} Port 8001 is in both config and active rules"
fi
echo ""

echo "4. Test connectivity from Tailscale IP"
echo "----------------------------------------"
VEGA_IP=$(tailscale ip -4 2>/dev/null || echo "")
if [[ -n "${VEGA_IP}" ]]; then
    echo "Vega Tailscale IP: ${VEGA_IP}"
    echo -n "Testing ${VEGA_IP}:8001/health from localhost... "
    if curl -s --max-time 2 http://${VEGA_IP}:8001/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Works"
    else
        echo -e "${RED}✗${NC} Failed"
        echo "  This suggests the firewall is blocking it"
    fi
else
    echo "Could not get Tailscale IP"
fi
echo ""

echo "============================================================================"
echo "Summary"
echo "============================================================================"
if sudo grep -q "8001" /etc/nftables.conf 2>/dev/null; then
    if sudo nft list ruleset 2>/dev/null | grep -q "8001"; then
        echo -e "${GREEN}Firewall is correctly configured${NC}"
        echo "If it still doesn't work, check:"
        echo "  1. Service is bound to 0.0.0.0:8001 (not 127.0.0.1)"
        echo "  2. Tailscale connectivity: tailscale ping rigel"
    else
        echo -e "${YELLOW}Firewall config has 8001 but rules not active${NC}"
        echo "Reload firewall: sudo nft -f /etc/nftables.conf"
    fi
else
    echo -e "${RED}Firewall config does NOT have 8001${NC}"
    echo "Redeploy firewall: ./scripts/run-ansible.sh prod vega foundation --tags firewall_nftables"
fi
echo "============================================================================"
