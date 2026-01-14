#!/bin/bash
# Check Tailscale DNS configuration and split-horizon DNS setup

set -e

echo "========================================"
echo "Tailscale DNS Configuration Check"
echo "========================================"

echo ""
echo "=== Local Machine DNS Configuration ==="
echo "Primary DNS servers:"
scutil --dns | grep -A1 "nameserver\[0\]" | head -10

echo ""
echo "=== Tailscale Status ==="
tailscale status | grep -E "(rigel|vega|mpnas)" || echo "No Tailscale peers found"

echo ""
echo "=== Tailscale DNS Settings ==="
# Get Tailscale DNS configuration without python
TAILSCALE_JSON=$(tailscale status --json 2>/dev/null)
if [ -n "$TAILSCALE_JSON" ]; then
    echo "MagicDNS Suffix: $(echo "$TAILSCALE_JSON" | grep -o '"MagicDNSSuffix":"[^"]*"' | cut -d'"' -f4)"
    echo "MagicDNS Enabled: $(echo "$TAILSCALE_JSON" | grep -o '"MagicDNSEnabled":[^,}]*' | cut -d':' -f2)"
else
    echo "Unable to get Tailscale DNS settings"
fi

echo ""
echo "=== Testing DNS Resolution ==="

echo "1. Testing Tailscale MagicDNS (100.100.100.100):"
dig @100.100.100.100 aispector.exnada.com +timeout=2 +tries=1 +short || echo "   ❌ FAILED - MagicDNS not forwarding to rigel"

echo ""
echo "2. Testing rigel CoreDNS directly (100.116.21.120):"
dig @100.116.21.120 aispector.exnada.com +timeout=2 +tries=1 +short || echo "   ❌ FAILED - CoreDNS not responding"

echo ""
echo "3. Testing default system DNS:"
dig aispector.exnada.com +timeout=2 +tries=1 +short || echo "   ❌ FAILED - System DNS not resolving"

echo ""
echo "=== Diagnosis ==="
if dig @100.116.21.120 aispector.exnada.com +timeout=2 +tries=1 +short > /dev/null 2>&1; then
    echo "✅ rigel CoreDNS is working correctly"

    if dig @100.100.100.100 aispector.exnada.com +timeout=2 +tries=1 +short > /dev/null 2>&1; then
        echo "✅ Tailscale MagicDNS is forwarding to rigel"
        echo "✅ Split DNS configuration is correct"
    else
        echo "❌ Tailscale MagicDNS is NOT forwarding to rigel"
        echo ""
        echo "ACTION REQUIRED:"
        echo "Configure split DNS in Tailscale Admin Console:"
        echo "  1. Go to: https://login.tailscale.com/admin/dns"
        echo "  2. Add Split DNS configuration:"
        echo "     - Domain: exnada.com"
        echo "     - Nameserver: 100.116.21.120 (rigel)"
        echo ""
        echo "OR add rigel as a global nameserver:"
        echo "  1. Go to: https://login.tailscale.com/admin/dns"
        echo "  2. Click 'Add nameserver'"
        echo "  3. Enter: 100.116.21.120"
    fi
else
    echo "❌ rigel CoreDNS is not responding"
    echo "Check that CoreDNS service is running on rigel:"
    echo "  ssh rigel 'systemctl status coredns'"
fi

echo ""
echo "========================================"
