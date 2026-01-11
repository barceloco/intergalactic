#!/bin/bash
# Check if ACME challenge DNS records exist
# Run this while certificate issuance is in progress

set -euo pipefail

DOMAIN="exnada.com"

echo "============================================================================"
echo "ACME Challenge DNS Record Check"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_record() {
    local record_name="$1"
    local resolver="$2"
    
    echo -n "Checking ${record_name} via ${resolver}... "
    result=$(dig @${resolver} ${record_name} TXT +short 2>/dev/null || echo "")
    if [[ -n "${result}" ]]; then
        echo -e "${GREEN}✓ FOUND${NC}"
        echo "  Value: ${result}"
        return 0
    else
        echo -e "${RED}✗ NOT FOUND${NC}"
        return 1
    fi
}

echo "Checking _acme-challenge.${DOMAIN} TXT record:"
echo "----------------------------------------"
found=false
for resolver in "8.8.8.8" "8.8.4.4" "1.1.1.1" "208.67.222.222"; do
    if check_record "_acme-challenge.${DOMAIN}" "${resolver}"; then
        found=true
    fi
done
echo ""

echo "Checking _acme-challenge.*.${DOMAIN} TXT record (wildcard):"
echo "----------------------------------------"
for resolver in "8.8.8.8" "8.8.4.4" "1.1.1.1" "208.67.222.222"; do
    if check_record "_acme-challenge.*.${DOMAIN}" "${resolver}"; then
        found=true
    fi
done
echo ""

if [[ "${found}" == "false" ]]; then
    echo -e "${YELLOW}⚠ No ACME challenge records found${NC}"
    echo ""
    echo "Possible causes:"
    echo "1. GoDaddy API didn't create the records"
    echo "2. DNS propagation delay (can take 5-10 minutes)"
    echo "3. Records created in wrong DNS zone"
    echo ""
    echo "Next steps:"
    echo "1. Check GoDaddy DNS management panel manually"
    echo "2. Look for _acme-challenge TXT records"
    echo "3. Wait a few minutes and check again"
    echo "4. Verify GoDaddy API credentials have DNS write permissions"
fi

echo ""
echo "============================================================================"
