#!/bin/bash
# Clean up duplicate _acme-challenge DNS records from GoDaddy
# This script removes old ACME challenge records that are blocking certificate issuance

set -euo pipefail

DOMAIN="exnada.com"
SUBDOMAINS=("aispector" "dev" "mpnas")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if API credentials are set
if [[ -z "${GODADDY_API_KEY:-}" ]] || [[ -z "${GODADDY_API_SECRET:-}" ]]; then
    log_error "GoDaddy API credentials not set"
    log_info "Set GODADDY_API_KEY and GODADDY_API_SECRET environment variables"
    exit 1
fi

log_info "Cleaning up duplicate _acme-challenge DNS records for ${DOMAIN}"

for subdomain in "${SUBDOMAINS[@]}"; do
    RECORD_NAME="_acme-challenge.${subdomain}"
    log_info "Checking records for ${RECORD_NAME}..."
    
    # Get all TXT records for this subdomain
    RESPONSE=$(curl -s -X GET \
        "https://api.godaddy.com/v1/domains/${DOMAIN}/records/TXT/${RECORD_NAME}" \
        -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
        -H "Content-Type: application/json" 2>&1)
    
    if echo "${RESPONSE}" | grep -q "NOT_FOUND\|404"; then
        log_info "  No records found for ${RECORD_NAME}"
        continue
    fi
    
    # Count records
    RECORD_COUNT=$(echo "${RESPONSE}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "0")
    
    if [[ "${RECORD_COUNT}" == "0" ]]; then
        log_info "  No records found for ${RECORD_NAME}"
        continue
    fi
    
    log_warn "  Found ${RECORD_COUNT} record(s) for ${RECORD_NAME}"
    
    # Delete all TXT records for this subdomain
    log_info "  Deleting all TXT records for ${RECORD_NAME}..."
    DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE \
        "https://api.godaddy.com/v1/domains/${DOMAIN}/records/TXT/${RECORD_NAME}" \
        -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
        -H "Content-Type: application/json" 2>&1)
    
    HTTP_CODE=$(echo "${DELETE_RESPONSE}" | tail -1)
    
    if [[ "${HTTP_CODE}" == "204" ]]; then
        log_info "  ✓ Successfully deleted records for ${RECORD_NAME}"
    elif [[ "${HTTP_CODE}" == "404" ]]; then
        log_info "  No records to delete for ${RECORD_NAME}"
    else
        log_error "  Failed to delete records for ${RECORD_NAME} (HTTP ${HTTP_CODE})"
        echo "${DELETE_RESPONSE}" | head -1
    fi
done

log_info "Cleanup complete. Wait a few minutes for DNS propagation, then try certificate issuance again."
