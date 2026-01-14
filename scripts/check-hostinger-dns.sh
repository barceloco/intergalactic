#!/bin/bash
# Check DNS records that might conflict with ACME challenge

DOMAIN="exnada.com"

echo "Checking DNS records for ${DOMAIN}..."
echo ""

echo "1. Checking for CNAME records (CNAME conflicts prevent TXT records):"
echo "----------------------------------------"
dig _acme-challenge.${DOMAIN} CNAME +short
dig _acme-challenge.*.${DOMAIN} CNAME +short
echo ""

echo "2. Checking for any existing TXT records:"
echo "----------------------------------------"
dig _acme-challenge.${DOMAIN} TXT +short
dig _acme-challenge.*.${DOMAIN} TXT +short
echo ""

echo "3. Checking root domain for CNAME (wildcard CNAME prevents wildcard TXT):"
echo "----------------------------------------"
dig ${DOMAIN} CNAME +short
dig *.${DOMAIN} CNAME +short
echo ""

echo "4. Checking if domain has CNAME at root (common issue):"
echo "----------------------------------------"
dig @8.8.8.8 ${DOMAIN} ANY +short | grep -i cname || echo "No CNAME found"
echo ""

echo "5. Testing Hostinger API token (if available):"
echo "----------------------------------------"
if [[ -f /etc/lego/hostinger_token ]]; then
    echo "Token file exists: $(wc -c < /etc/lego/hostinger_token) bytes"
    echo "Token preview: $(head -c 10 /etc/lego/hostinger_token)..."
else
    echo "Token file not found"
fi
