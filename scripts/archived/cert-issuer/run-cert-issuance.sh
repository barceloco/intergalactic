#!/bin/bash
# Manual certificate issuance script
# Run this on rigel to issue certificates manually
# Usage: sudo ./run-cert-issuance.sh [staging|production]

set -euo pipefail

CA_SERVER="${1:-staging}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Configuration
CONFIG_DIR="/etc/lego"
ENV_FILE="${CONFIG_DIR}/lego.env"
API_KEY_FILE="${CONFIG_DIR}/godaddy_api_key"
API_SECRET_FILE="${CONFIG_DIR}/godaddy_api_secret"
LEGO_DATA_DIR="/opt/lego/data"
CERT_DIR="/opt/traefik/certs"

# Validate environment
if [[ ! -f "${ENV_FILE}" ]]; then
    log_error "Environment file not found: ${ENV_FILE}"
    exit 1
fi

if [[ ! -f "${API_KEY_FILE}" ]] || [[ ! -f "${API_SECRET_FILE}" ]]; then
    log_error "GoDaddy API credentials not found"
    exit 1
fi

# Load environment
set -a
source "${ENV_FILE}"
set +a

# Read API credentials
GODADDY_API_KEY=$(cat "${API_KEY_FILE}" | tr -d '\n\r ')
GODADDY_API_SECRET=$(cat "${API_SECRET_FILE}" | tr -d '\n\r ')

if [[ -z "${GODADDY_API_KEY}" ]] || [[ -z "${GODADDY_API_SECRET}" ]]; then
    log_error "GoDaddy API credentials are empty"
    exit 1
fi

# Determine CA server
if [[ "${CA_SERVER}" == "production" ]]; then
    LEGO_CA_SERVER="https://acme-v02.api.letsencrypt.org/directory"
    log_info "Using Let's Encrypt PRODUCTION"
else
    LEGO_CA_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
    log_warn "Using Let's Encrypt STAGING (test certificates)"
fi

# Override CA server if set in env
if [[ -n "${LEGO_CA_SERVER:-}" ]]; then
    LEGO_CA_SERVER="${LEGO_CA_SERVER}"
fi

log_info "Domain: ${LEGO_DOMAINS}"
log_info "Email: ${LEGO_EMAIL}"
log_info "CA Server: ${LEGO_CA_SERVER}"

# Check if certificate already exists
CERT_EXISTS=false
if [[ -f "${LEGO_DATA_DIR}/certificates/_.${LEGO_DOMAINS%%,*}.crt" ]] || \
   [[ -f "${LEGO_DATA_DIR}/certificates/${LEGO_DOMAINS%%,*}.crt" ]]; then
    CERT_EXISTS=true
    log_info "Certificate exists, will attempt renewal"
fi

# Build lego command
LEGO_ARGS=(
    --path /data
    --email "${LEGO_EMAIL}"
    --dns godaddy
    --dns.propagation-wait 60s  # Wait 60 seconds max for propagation (fail fast, bypasses ANS check)
    --accept-tos
    --server "${LEGO_CA_SERVER}"
)

# Add domains
IFS=',' read -ra DOMAINS <<< "${LEGO_DOMAINS}"
for domain in "${DOMAINS[@]}"; do
    LEGO_ARGS+=(--domains "${domain}")
done

# Run lego
log_info "Running lego in Docker container..."
log_info "This may take several minutes (DNS propagation can take up to 5 minutes)"

if [[ "${CERT_EXISTS}" == "true" ]]; then
    log_info "Attempting certificate renewal..."
    if docker run --rm \
        --network host \
        -v "${LEGO_DATA_DIR}:/data:rw" \
        -v "${CONFIG_DIR}:/etc/lego:ro" \
        -v "${CERT_DIR}:/certs:rw" \
        -e GODADDY_API_KEY="${GODADDY_API_KEY}" \
        -e GODADDY_API_SECRET="${GODADDY_API_SECRET}" \
        -e GODADDY_PROPAGATION_TIMEOUT="${GODADDY_PROPAGATION_TIMEOUT:-60}" \
        -e GODADDY_POLLING_INTERVAL="${GODADDY_POLLING_INTERVAL:-10}" \
        -e GODADDY_TTL="${GODADDY_TTL:-600}" \
        --dns "8.8.8.8" \
        --dns "8.8.4.4" \
        goacme/lego:v4.31.0 \
        "${LEGO_ARGS[@]}" renew --days 30; then
        log_info "Certificate renewal completed"
    else
        EXIT_CODE=$?
        if [[ ${EXIT_CODE} -eq 1 ]]; then
            log_info "Certificate is still valid, no renewal needed"
        else
            log_error "Certificate renewal failed with exit code ${EXIT_CODE}"
            exit ${EXIT_CODE}
        fi
    fi
else
    log_info "Issuing new certificate..."
    if docker run --rm \
        --network host \
        -v "${LEGO_DATA_DIR}:/data:rw" \
        -v "${CONFIG_DIR}:/etc/lego:ro" \
        -v "${CERT_DIR}:/certs:rw" \
        -e GODADDY_API_KEY="${GODADDY_API_KEY}" \
        -e GODADDY_API_SECRET="${GODADDY_API_SECRET}" \
        -e GODADDY_PROPAGATION_TIMEOUT="${GODADDY_PROPAGATION_TIMEOUT:-60}" \
        -e GODADDY_POLLING_INTERVAL="${GODADDY_POLLING_INTERVAL:-10}" \
        -e GODADDY_TTL="${GODADDY_TTL:-600}" \
        --dns "8.8.8.8" \
        --dns "8.8.4.4" \
        goacme/lego:v4.31.0 \
        "${LEGO_ARGS[@]}" run; then
        log_info "Certificate issued successfully"
    else
        log_error "Certificate issuance failed"
        exit 1
    fi
fi

# Deploy certificates
if [[ -f "${CONFIG_DIR}/deploy-internal-certs.sh" ]] && [[ -x "${CONFIG_DIR}/deploy-internal-certs.sh" ]]; then
    log_info "Deploying certificates to Traefik..."
    "${CONFIG_DIR}/deploy-internal-certs.sh" || {
        log_error "Certificate deployment failed"
        exit 1
    }
    log_info "Certificates deployed successfully"
else
    log_warn "Deploy script not found or not executable"
fi

# Verify certificates
log_info "Verifying certificates..."
if [[ -f "${CERT_DIR}/exnada.com.crt" ]] || [[ -f "${CERT_DIR}/_.exnada.com.crt" ]]; then
    log_info "✓ Certificates are in place"
    ls -lh "${CERT_DIR}"/*.crt 2>/dev/null || true
else
    log_warn "Certificates not found in ${CERT_DIR}"
fi

log_info "Done!"
