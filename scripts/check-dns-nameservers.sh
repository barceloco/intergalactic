#!/bin/bash
# Check DNS nameserver configuration for exnada.com
# This helps diagnose why lego is trying to query rigel.exnada.com as a nameserver

set -euo pipefail

DOMAIN="exnada.com"

echo "============================================================================"
echo "DNS Nameserver Diagnostic for ${DOMAIN}"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. Checking NS records for ${DOMAIN}"
echo "----------------------------------------"
echo "Using Google DNS (8.8.8.8):"
dig @8.8.8.8 ${DOMAIN} NS +short || echo "No NS records found"
echo ""

echo "Using Cloudflare DNS (1.1.1.1):"
dig @1.1.1.1 ${DOMAIN} NS +short || echo "No NS records found"
echo ""

echo "Using system resolver:"
dig ${DOMAIN} NS +short || echo "No NS records found"
echo ""

echo "2. Checking SOA record for ${DOMAIN}"
echo "----------------------------------------"
dig @8.8.8.8 ${DOMAIN} SOA +short || echo "No SOA record found"
echo ""

echo "3. Checking if rigel.exnada.com is listed as nameserver"
echo "----------------------------------------"
NS_RECORDS=$(dig @8.8.8.8 ${DOMAIN} NS +short)
if echo "${NS_RECORDS}" | grep -q "rigel.exnada.com"; then
    echo -e "${RED}✗ PROBLEM FOUND: rigel.exnada.com is listed as a nameserver${NC}"
    echo "This is incorrect - rigel.exnada.com should NOT be a nameserver"
    echo ""
    echo "Current NS records:"
    echo "${NS_RECORDS}"
    echo ""
    echo "ACTION REQUIRED:"
    echo "1. Log into GoDaddy DNS management"
    echo "2. Check NS records for exnada.com"
    echo "3. Remove any NS records pointing to rigel.exnada.com"
    echo "4. Ensure only GoDaddy nameservers are listed (e.g., ns1.godaddy.com)"
else
    echo -e "${GREEN}✓ rigel.exnada.com is NOT listed as a nameserver${NC}"
fi
echo ""

echo "4. Checking authoritative nameservers (from SOA)"
echo "----------------------------------------"
AUTH_NS=$(dig @8.8.8.8 ${DOMAIN} SOA +short | awk '{print $1}' | sed 's/\.$//')
if [[ -n "${AUTH_NS}" ]]; then
    echo "Authoritative nameserver from SOA: ${AUTH_NS}"
    # Try to resolve it
    if dig @8.8.8.8 ${AUTH_NS} A +short >/dev/null 2>&1; then
        echo -e "${GREEN}✓ ${AUTH_NS} resolves${NC}"
    else
        echo -e "${RED}✗ ${AUTH_NS} does NOT resolve${NC}"
    fi
else
    echo "Could not determine authoritative nameserver"
fi
echo ""

echo "5. Checking _acme-challenge TXT record (if exists)"
echo "----------------------------------------"
ACME_TXT=$(dig @8.8.8.8 _acme-challenge.${DOMAIN} TXT +short 2>/dev/null || echo "")
if [[ -n "${ACME_TXT}" ]]; then
    echo "Found: ${ACME_TXT}"
    echo -e "${YELLOW}⚠ This might be a leftover from a previous attempt${NC}"
else
    echo "No _acme-challenge TXT record found (expected if no active challenge)"
fi
echo ""

echo "6. Testing GoDaddy API connectivity"
echo "----------------------------------------"
if curl -s --max-time 5 https://api.godaddy.com/v1/domains/${DOMAIN} >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Can reach GoDaddy API${NC}"
else
    echo -e "${YELLOW}⚠ Cannot reach GoDaddy API (may require authentication)${NC}"
fi
echo ""

echo "============================================================================"
echo "Diagnostic complete"
echo "============================================================================"
echo ""
echo "RECOMMENDATION:"
echo "If rigel.exnada.com appears as a nameserver, you MUST fix this in GoDaddy DNS:"
echo "1. Go to https://dcc.godaddy.com/manage/exnada.com/dns"
echo "2. Check the NS (Nameserver) records"
echo "3. Remove any records pointing to rigel.exnada.com"
echo "4. Ensure only GoDaddy nameservers are present"
echo ""
