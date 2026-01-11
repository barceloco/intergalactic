#!/bin/bash
# Fast development iteration script for CoreDNS configuration
# Run this directly on rigel to test Corefile changes without running Ansible
# Usage: ./scripts/test-coredns-config.sh

set -euo pipefail

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

COREDNS_DATA_DIR="${COREDNS_DATA_DIR:-/opt/coredns}"
COREFILE="${COREDNS_DATA_DIR}/Corefile"
COMPOSE_FILE="${COREDNS_DATA_DIR}/docker-compose.yml"
CONTAINER_NAME="${COREDNS_CONTAINER_NAME:-coredns}"
DOMAIN="${COREDNS_DOMAIN:-exnada.com}"

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (or with sudo)"
    exit 1
fi

# Check if Corefile exists
if [[ ! -f "${COREFILE}" ]]; then
    log_error "Corefile not found: ${COREFILE}"
    exit 1
fi

log_info "Validating Corefile syntax..."
if docker run --rm -v "${COREFILE}:/Corefile:ro" coredns/coredns:latest -conf /Corefile -validate 2>&1; then
    log_info "✓ Corefile syntax is valid"
else
    log_error "✗ Corefile syntax validation failed"
    exit 1
fi

log_info "Restarting CoreDNS container..."
if docker compose -f "${COMPOSE_FILE}" restart "${CONTAINER_NAME}" 2>&1; then
    log_info "✓ CoreDNS container restarted"
else
    log_error "✗ Failed to restart CoreDNS container"
    exit 1
fi

# Wait for CoreDNS to be ready
log_info "Waiting for CoreDNS to be ready..."
sleep 2

# Test internal hosts
log_info "Testing internal hosts..."
INTERNAL_HOSTS=("mpnas" "aispector" "dev")
FAILED=0

for host in "${INTERNAL_HOSTS[@]}"; do
    if dig @127.0.0.1 "${host}.${DOMAIN}" A +short | grep -q "^100\."; then
        log_info "✓ ${host}.${DOMAIN} resolves correctly"
    else
        log_error "✗ ${host}.${DOMAIN} failed to resolve"
        FAILED=1
    fi
done

# Test external forwarding
log_info "Testing external subdomain forwarding..."
if dig @127.0.0.1 "www.${DOMAIN}" A +short | grep -q "."; then
    log_info "✓ www.${DOMAIN} forwards correctly"
else
    log_error "✗ www.${DOMAIN} failed to forward"
    FAILED=1
fi

# Test unknown subdomain forwarding
log_info "Testing unknown subdomain forwarding..."
if dig @127.0.0.1 "foo.${DOMAIN}" A +short 2>&1 | grep -q "." || dig @127.0.0.1 "foo.${DOMAIN}" A +short 2>&1 | grep -q "NXDOMAIN"; then
    log_info "✓ foo.${DOMAIN} forwards correctly (or returns NXDOMAIN from upstream)"
else
    log_warn "? foo.${DOMAIN} may not be forwarding correctly"
fi

# Test health endpoint
log_info "Testing health endpoint..."
if curl -sf "http://127.0.0.1:8080/health" > /dev/null; then
    log_info "✓ Health endpoint responds"
else
    log_error "✗ Health endpoint not responding"
    FAILED=1
fi

# Test ready endpoint
log_info "Testing ready endpoint..."
if curl -sf "http://127.0.0.1:8181/ready" > /dev/null; then
    log_info "✓ Ready endpoint responds"
else
    log_error "✗ Ready endpoint not responding"
    FAILED=1
fi

# Summary
if [[ ${FAILED} -eq 0 ]]; then
    log_info "✓ All tests passed!"
    exit 0
else
    log_error "✗ Some tests failed"
    exit 1
fi
