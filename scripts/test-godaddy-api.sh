#!/bin/bash
# Test GoDaddy API connectivity and DNS record creation
# This helps verify if the API credentials work

set -euo pipefail

CONFIG_DIR="/etc/lego"
API_KEY_FILE="${CONFIG_DIR}/godaddy_api_key"
API_SECRET_FILE="${CONFIG_DIR}/godaddy_api_secret"
DOMAIN="exnada.com"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================================================"
echo "GoDaddy API Test"
echo "============================================================================"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗${NC} This script must be run as root"
    exit 1
fi

# Read credentials
if [[ ! -f "${API_KEY_FILE}" ]] || [[ ! -f "${API_SECRET_FILE}" ]]; then
    echo -e "${RED}✗${NC} API credential files not found"
    exit 1
fi

GODADDY_API_KEY=$(cat "${API_KEY_FILE}" | tr -d '\n\r ')
GODADDY_API_SECRET=$(cat "${API_SECRET_FILE}" | tr -d '\n\r ')

if [[ -z "${GODADDY_API_KEY}" ]] || [[ -z "${GODADDY_API_SECRET}" ]]; then
    echo -e "${RED}✗${NC} API credentials are empty"
    exit 1
fi

echo "1. Testing API connectivity"
echo "----------------------------------------"
if curl -s --max-time 10 \
    -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
    "https://api.godaddy.com/v1/domains/${DOMAIN}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Can reach GoDaddy API"
else
    echo -e "${RED}✗${NC} Cannot reach GoDaddy API"
    echo "  Check: API key and secret are correct"
    echo "  Check: API key has DNS management permissions"
    exit 1
fi
echo ""

echo "2. Checking domain DNS records"
echo "----------------------------------------"
DNS_RECORDS=$(curl -s --max-time 10 \
    -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
    "https://api.godaddy.com/v1/domains/${DOMAIN}/records/TXT/_acme-challenge" 2>/dev/null || echo "")

if [[ -n "${DNS_RECORDS}" ]] && [[ "${DNS_RECORDS}" != "[]" ]]; then
    echo -e "${YELLOW}⚠${NC} Found existing _acme-challenge TXT records:"
    echo "${DNS_RECORDS}" | python3 -m json.tool 2>/dev/null || echo "${DNS_RECORDS}"
    echo ""
    echo "These may need to be deleted before issuing new certificates"
else
    echo -e "${GREEN}✓${NC} No existing _acme-challenge records (clean state)"
fi
echo ""

echo "3. Testing DNS record creation (dry run)"
echo "----------------------------------------"
TEST_RECORD="test-$(date +%s)"
echo "Would create: _acme-challenge.${DOMAIN} TXT ${TEST_RECORD}"
echo ""
echo "To actually test creation, run:"
echo "  curl -X PATCH \\"
echo "    -H 'Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '[{\"data\":\"${TEST_RECORD}\",\"ttl\":600}]' \\"
echo "    'https://api.godaddy.com/v1/domains/${DOMAIN}/records/TXT/_acme-challenge'"
echo ""

echo "============================================================================"
echo "Test complete"
echo "============================================================================"
