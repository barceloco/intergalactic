#!/bin/bash
# Test creating and verifying a DNS TXT record via GoDaddy API
# This helps diagnose if the API can actually create records that propagate

set -euo pipefail

CONFIG_DIR="/etc/lego"
API_KEY_FILE="${CONFIG_DIR}/godaddy_api_key"
API_SECRET_FILE="${CONFIG_DIR}/godaddy_api_secret"
DOMAIN="exnada.com"
TEST_VALUE="test-$(date +%s)-$(openssl rand -hex 4)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================================================"
echo "GoDaddy DNS Record Creation Test"
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

echo "Test value: ${TEST_VALUE}"
echo "Record: _acme-challenge.${DOMAIN} TXT ${TEST_VALUE}"
echo ""

echo "1. Verifying domain access"
echo "----------------------------------------"
DOMAIN_CHECK=$(curl -s -w "\n%{http_code}" --max-time 10 \
    -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
    "https://api.godaddy.com/v1/domains/${DOMAIN}" 2>&1)

DOMAIN_HTTP_CODE=$(echo "${DOMAIN_CHECK}" | tail -n1)
DOMAIN_BODY=$(echo "${DOMAIN_CHECK}" | head -n-1)

if [[ "${DOMAIN_HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓${NC} Domain found in GoDaddy account"
    echo "${DOMAIN_BODY}" | python3 -m json.tool 2>/dev/null | head -10 || echo "${DOMAIN_BODY}" | head -5
else
    echo -e "${RED}✗${NC} Domain not found or not accessible (HTTP ${DOMAIN_HTTP_CODE})"
    echo "Response: ${DOMAIN_BODY}"
    echo ""
    echo "Possible issues:"
    echo "  - Domain ${DOMAIN} is not in this GoDaddy account"
    echo "  - API key doesn't have access to this domain"
    echo "  - Domain is managed by a different GoDaddy account"
    exit 1
fi
echo ""

echo "2. Checking existing TXT records for _acme-challenge"
echo "----------------------------------------"
EXISTING_RECORDS=$(curl -s -w "\n%{http_code}" --max-time 10 \
    -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
    "https://api.godaddy.com/v1/domains/${DOMAIN}/records/TXT/_acme-challenge" 2>&1)

EXISTING_HTTP_CODE=$(echo "${EXISTING_RECORDS}" | tail -n1)
EXISTING_BODY=$(echo "${EXISTING_RECORDS}" | head -n-1)

if [[ "${EXISTING_HTTP_CODE}" == "200" ]]; then
    if [[ "${EXISTING_BODY}" != "[]" ]] && [[ -n "${EXISTING_BODY}" ]]; then
        echo -e "${YELLOW}⚠${NC} Existing records found:"
        echo "${EXISTING_BODY}" | python3 -m json.tool 2>/dev/null || echo "${EXISTING_BODY}"
    else
        echo -e "${GREEN}✓${NC} No existing records (clean state)"
    fi
elif [[ "${EXISTING_HTTP_CODE}" == "404" ]]; then
    echo -e "${GREEN}✓${NC} No existing records (404 is normal for empty subdomain)"
else
    echo -e "${YELLOW}⚠${NC} Unexpected response (HTTP ${EXISTING_HTTP_CODE})"
    echo "Response: ${EXISTING_BODY}"
fi
echo ""

echo "3. Testing API key permissions"
echo "----------------------------------------"
# Try to list all DNS records to check permissions
LIST_RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 10 \
    -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
    "https://api.godaddy.com/v1/domains/${DOMAIN}/records" 2>&1)

LIST_HTTP_CODE=$(echo "${LIST_RESPONSE}" | tail -n1)
LIST_BODY=$(echo "${LIST_RESPONSE}" | head -n-1)

if [[ "${LIST_HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓${NC} Can read DNS records (has read permissions)"
    RECORD_COUNT=$(echo "${LIST_BODY}" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "unknown")
    echo "  Total DNS records: ${RECORD_COUNT}"
else
    echo -e "${RED}✗${NC} Cannot read DNS records (HTTP ${LIST_HTTP_CODE})"
    echo "  This suggests API key lacks DNS read permissions"
    echo "  Response: ${LIST_BODY}"
fi
echo ""

echo "4. Creating DNS record via GoDaddy API"
echo "----------------------------------------"
# Try PATCH first (updates existing records)
echo "Attempting PATCH (update existing)..."
PATCH_RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 10 \
    -X PATCH \
    -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
    -H "Content-Type: application/json" \
    -d "[{\"data\":\"${TEST_VALUE}\",\"ttl\":600}]" \
    "https://api.godaddy.com/v1/domains/${DOMAIN}/records/TXT/_acme-challenge" 2>&1)

PATCH_HTTP_CODE=$(echo "${PATCH_RESPONSE}" | tail -n1)
PATCH_BODY=$(echo "${PATCH_RESPONSE}" | head -n-1)

if [[ "${PATCH_HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓${NC} Record created/updated via PATCH (HTTP ${PATCH_HTTP_CODE})"
    RESPONSE="${PATCH_RESPONSE}"
    HTTP_CODE="${PATCH_HTTP_CODE}"
    BODY="${PATCH_BODY}"
else
    echo "  PATCH failed (HTTP ${PATCH_HTTP_CODE}) - trying PUT..."
    # Try PUT (replaces all records for the subdomain)
    PUT_RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 10 \
        -X PUT \
        -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
        -H "Content-Type: application/json" \
        -d "[{\"data\":\"${TEST_VALUE}\",\"ttl\":600}]" \
        "https://api.godaddy.com/v1/domains/${DOMAIN}/records/TXT/_acme-challenge" 2>&1)
    
    PUT_HTTP_CODE=$(echo "${PUT_RESPONSE}" | tail -n1)
    PUT_BODY=$(echo "${PUT_RESPONSE}" | head -n-1)
    
    if [[ "${PUT_HTTP_CODE}" == "200" ]]; then
        echo -e "${GREEN}✓${NC} Record created via PUT (HTTP ${PUT_HTTP_CODE})"
        RESPONSE="${PUT_RESPONSE}"
        HTTP_CODE="${PUT_HTTP_CODE}"
        BODY="${PUT_BODY}"
    else
        echo -e "${RED}✗${NC} Both PATCH and PUT failed"
        echo "PATCH response (HTTP ${PATCH_HTTP_CODE}): ${PATCH_BODY}"
        echo "PUT response (HTTP ${PUT_HTTP_CODE}): ${PUT_BODY}"
        echo ""
        echo "Possible issues:"
        echo "  - API key lacks DNS write permissions"
        echo "  - Domain DNS is managed externally (not by GoDaddy)"
        echo "  - Domain is locked or in transfer status"
        exit 1
    fi
fi

HTTP_CODE=$(echo "${RESPONSE}" | tail -n1)
BODY=$(echo "${RESPONSE}" | head -n-1)

if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓${NC} Record created successfully (HTTP ${HTTP_CODE})"
    echo "Response: ${BODY}"
else
    echo -e "${RED}✗${NC} Failed to create record (HTTP ${HTTP_CODE})"
    echo "Response: ${BODY}"
    exit 1
fi
echo ""

echo "2. Verifying record via GoDaddy API"
echo "----------------------------------------"
sleep 2
API_RECORDS=$(curl -s --max-time 10 \
    -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
    "https://api.godaddy.com/v1/domains/${DOMAIN}/records/TXT/_acme-challenge" 2>/dev/null || echo "")

if echo "${API_RECORDS}" | grep -q "${TEST_VALUE}"; then
    echo -e "${GREEN}✓${NC} Record found in GoDaddy API"
    echo "${API_RECORDS}" | python3 -m json.tool 2>/dev/null || echo "${API_RECORDS}"
else
    echo -e "${RED}✗${NC} Record not found in GoDaddy API"
    echo "Response: ${API_RECORDS}"
fi
echo ""

echo "5. Waiting for DNS propagation (checking every 5 seconds, up to 2 minutes)"
echo "----------------------------------------"
FOUND=false
for i in {1..24}; do
    sleep 5
    echo -n "Attempt ${i}/24: "
    
    # Check multiple resolvers
    for resolver in "8.8.8.8" "8.8.4.4" "1.1.1.1"; do
        RESULT=$(dig @${resolver} _acme-challenge.${DOMAIN} TXT +short 2>/dev/null | grep -o "${TEST_VALUE}" || echo "")
        if [[ -n "${RESULT}" ]]; then
            echo -e "${GREEN}✓ FOUND via ${resolver}${NC}"
            FOUND=true
            break 2
        fi
    done
    
    if [[ "${FOUND}" == "false" ]]; then
        echo "not found yet..."
    fi
done
echo ""

if [[ "${FOUND}" == "true" ]]; then
    echo -e "${GREEN}✓${NC} DNS record propagated successfully!"
else
    echo -e "${YELLOW}⚠${NC} DNS record not found after 2 minutes"
    echo "This could indicate:"
    echo "  - DNS propagation delay (normal for GoDaddy, can take 5-10 minutes)"
    echo "  - DNS caching issues"
    echo "  - GoDaddy nameserver configuration issue"
fi
echo ""

echo "7. Cleaning up test record"
echo "----------------------------------------"
DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 10 \
    -X DELETE \
    -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
    "https://api.godaddy.com/v1/domains/${DOMAIN}/records/TXT/_acme-challenge" 2>&1)

DELETE_HTTP_CODE=$(echo "${DELETE_RESPONSE}" | tail -n1)
if [[ "${DELETE_HTTP_CODE}" == "204" ]] || [[ "${DELETE_HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓${NC} Test record deleted (HTTP ${DELETE_HTTP_CODE})"
else
    echo -e "${YELLOW}⚠${NC} Could not delete test record (HTTP ${DELETE_HTTP_CODE})"
    echo "You may need to delete it manually from GoDaddy DNS panel"
fi
echo ""

echo "============================================================================"
echo "Test complete"
echo "============================================================================"
