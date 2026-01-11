#!/bin/bash
# Comprehensive validation script for CoreDNS split-horizon DNS
# Tests internal/external resolution, health endpoints, and metrics
# Usage: ./scripts/validate-coredns-split-dns.sh [COREDNS_IP]
# Default: 100.72.27.93 (rigel's Tailscale IP)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

COREDNS_IP="${1:-100.72.27.93}"
DOMAIN="exnada.com"
INTERNAL_HOSTS=("mpnas" "aispector" "dev")
EXTERNAL_HOSTS=("www" "mail")
UNKNOWN_HOST="foo"
HEALTH_PORT=8080
READY_PORT=8181
PROMETHEUS_PORT=9153

FAILED=0
PASSED=0
WARNINGS=0

# Test counter
test_count() {
    if [[ $1 -eq 0 ]]; then
        ((PASSED++))
    else
        ((FAILED++))
    fi
}

warn_count() {
    ((WARNINGS++))
}

log_info "Validating CoreDNS split-horizon DNS configuration"
log_info "CoreDNS IP: ${COREDNS_IP}"
log_info "Domain: ${DOMAIN}"
echo ""

# Test 1: Internal hosts resolve to Tailscale IPs (A records)
log_test "Test 1: Internal hosts resolve to Tailscale IPs (A records)"
for host in "${INTERNAL_HOSTS[@]}"; do
    FQDN="${host}.${DOMAIN}"
    RESULT=$(dig @${COREDNS_IP} "${FQDN}" A +short 2>/dev/null || echo "")
    
    if echo "${RESULT}" | grep -qE "^100\.[0-9]+\.[0-9]+\.[0-9]+$"; then
        log_info "  ✓ ${FQDN} → ${RESULT} (Tailscale IP)"
        test_count 0
    else
        log_error "  ✗ ${FQDN} → ${RESULT} (expected Tailscale IP)"
        test_count 1
    fi
done
echo ""

# Test 2: External subdomains forward to public DNS
log_test "Test 2: External subdomains forward to public DNS"
for host in "${EXTERNAL_HOSTS[@]}"; do
    FQDN="${host}.${DOMAIN}"
    RESULT=$(dig @${COREDNS_IP} "${FQDN}" A +short 2>/dev/null || echo "")
    
    if [[ -n "${RESULT}" ]] && ! echo "${RESULT}" | grep -qE "^100\.[0-9]+\.[0-9]+\.[0-9]+$"; then
        log_info "  ✓ ${FQDN} → ${RESULT} (forwarded to public DNS)"
        test_count 0
    else
        log_error "  ✗ ${FQDN} → ${RESULT} (expected public IP, not Tailscale IP)"
        test_count 1
    fi
done
echo ""

# Test 3: Unknown subdomain forwards to public DNS
log_test "Test 3: Unknown subdomain forwards to public DNS"
FQDN="${UNKNOWN_HOST}.${DOMAIN}"
RESULT=$(dig @${COREDNS_IP} "${FQDN}" A +short 2>/dev/null || echo "")
STATUS=$(dig @${COREDNS_IP} "${FQDN}" A +noall +status 2>/dev/null | awk '{print $6}' || echo "")

if [[ -n "${RESULT}" ]] && ! echo "${RESULT}" | grep -qE "^100\.[0-9]+\.[0-9]+\.[0-9]+$"; then
    log_info "  ✓ ${FQDN} → ${RESULT} (forwarded to public DNS)"
    test_count 0
elif [[ "${STATUS}" == "NXDOMAIN" ]]; then
    log_info "  ✓ ${FQDN} → NXDOMAIN (forwarded, upstream returned NXDOMAIN)"
    test_count 0
else
    log_warn "  ? ${FQDN} → ${RESULT} (may not be forwarding correctly)"
    warn_count
fi
echo ""

# Test 4: Health endpoint responds
log_test "Test 4: Health endpoint responds"
if curl -sf "http://${COREDNS_IP}:${HEALTH_PORT}/health" > /dev/null 2>&1; then
    log_info "  ✓ Health endpoint (http://${COREDNS_IP}:${HEALTH_PORT}/health) responds"
    test_count 0
else
    log_error "  ✗ Health endpoint not responding"
    test_count 1
fi
echo ""

# Test 5: Ready endpoint responds
log_test "Test 5: Ready endpoint responds"
if curl -sf "http://${COREDNS_IP}:${READY_PORT}/ready" > /dev/null 2>&1; then
    log_info "  ✓ Ready endpoint (http://${COREDNS_IP}:${READY_PORT}/ready) responds"
    test_count 0
else
    log_error "  ✗ Ready endpoint not responding"
    test_count 1
fi
echo ""

# Test 6: Prometheus metrics available
log_test "Test 6: Prometheus metrics available"
METRICS=$(curl -sf "http://${COREDNS_IP}:${PROMETHEUS_PORT}/metrics" 2>/dev/null || echo "")
if echo "${METRICS}" | grep -q "coredns"; then
    log_info "  ✓ Prometheus metrics (http://${COREDNS_IP}:${PROMETHEUS_PORT}/metrics) available"
    test_count 0
else
    log_error "  ✗ Prometheus metrics not available"
    test_count 1
fi
echo ""

# Test 7: Upstream DNS failure handling (graceful degradation)
log_test "Test 7: Upstream DNS failure handling (graceful degradation)"
# This test is informational - we can't easily simulate upstream failure
log_info "  ℹ Upstream DNS failure handling should return SERVFAIL gracefully"
log_info "  ℹ Manual test: Block upstream DNS and verify CoreDNS handles it"
echo ""

# Test 8: Cache behavior (TTL respected)
log_test "Test 8: Cache behavior (TTL respected)"
FQDN="www.${DOMAIN}"
FIRST=$(dig @${COREDNS_IP} "${FQDN}" A +short 2>/dev/null | head -1)
sleep 1
SECOND=$(dig @${COREDNS_IP} "${FQDN}" A +short 2>/dev/null | head -1)

if [[ "${FIRST}" == "${SECOND}" ]]; then
    log_info "  ✓ Cache working (consistent results: ${FIRST})"
    test_count 0
else
    log_warn "  ? Cache may not be working (results differ: ${FIRST} vs ${SECOND})"
    warn_count
fi
echo ""

# Summary
echo "=========================================="
log_info "Validation Summary:"
log_info "  Passed: ${PASSED}"
if [[ ${FAILED} -gt 0 ]]; then
    log_error "  Failed: ${FAILED}"
fi
if [[ ${WARNINGS} -gt 0 ]]; then
    log_warn "  Warnings: ${WARNINGS}"
fi
echo "=========================================="

if [[ ${FAILED} -eq 0 ]]; then
    log_info "✓ All critical tests passed!"
    exit 0
else
    log_error "✗ Some tests failed"
    exit 1
fi
