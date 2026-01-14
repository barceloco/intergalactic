#!/bin/bash
# Check ACME certificate status on Traefik
# Usage: ./scripts/check-acme-certificates.sh [host]

set -e

HOST=${1:-rigel}

echo "========================================"
echo "ACME Certificate Status Check"
echo "Host: ${HOST}"
echo "========================================"

echo ""
echo "=== ACME File Info ==="
ssh ${HOST} "ls -lh /opt/traefik/acme.json 2>/dev/null || echo 'acme.json not found'"

echo ""
echo "=== Extracting Certificate Domains ==="
# Parse acme.json without jq - extract domain names from JSON (handles both "main":"domain" and "main": "domain")
DOMAINS=$(ssh ${HOST} "sudo cat /opt/traefik/acme.json 2>/dev/null | grep -o '\"main\"[[:space:]]*:[[:space:]]*\"[^\"]*\"' | sed 's/.*\"\([^\"]*\)\".*/\1/' | sort -u" || echo "")
if [ -n "$DOMAINS" ]; then
    echo "$DOMAINS"
else
    echo "No certificates found or unable to read acme.json"
fi

echo ""
echo "=== Certificate Count ==="
CERT_COUNT=$(ssh ${HOST} "sudo cat /opt/traefik/acme.json 2>/dev/null | grep -c '\"main\":' || echo '0'")
echo "Total certificates: ${CERT_COUNT}"

echo ""
echo "=== Recent Certificate Activity in Traefik Logs ==="
CERT_LOGS=$(ssh ${HOST} "sudo docker logs traefik 2>&1 | grep -i 'certificate.*obtained\|certificate.*renewed' | tail -10" || echo "")
if [ -n "$CERT_LOGS" ]; then
    echo "$CERT_LOGS"
else
    echo "No recent certificate activity found"
fi

echo ""
echo "=== Test Certificate Validity via HTTPS ==="
# Test actual HTTPS connections
for domain in $DOMAINS; do
    if [ -n "$domain" ]; then
        echo ""
        echo "Testing ${domain}:"
        # Use rigel's Tailscale IP for connection
        CERT_INFO=$(echo | timeout 5 openssl s_client -servername ${domain} -connect 100.116.21.120:443 2>/dev/null | openssl x509 -noout -dates -subject 2>/dev/null || echo "")
        if [ -n "$CERT_INFO" ]; then
            echo "  ✅ Certificate valid"
            echo "$CERT_INFO" | sed 's/^/  /'
        else
            echo "  ❌ Cannot verify certificate (connection timeout or SSL error)"
        fi
    fi
done

echo ""
echo "========================================"
