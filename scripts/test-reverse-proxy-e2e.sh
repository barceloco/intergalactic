#!/bin/bash
# End-to-end test for reverse proxy
# Tests the complete flow: DNS → HTTPS → Traefik → Backend

set -euo pipefail

echo "============================================================================"
echo "Reverse Proxy End-to-End Test"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

test_step() {
    local name="$1"
    local command="$2"
    
    echo -n "Testing ${name}... "
    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_step_with_output() {
    local name="$1"
    local command="$2"
    
    echo "Testing ${name}..."
    echo "  Command: ${command}"
    OUTPUT=$(eval "$command" 2>&1)
    EXIT_CODE=$?
    
    if [[ ${EXIT_CODE} -eq 0 ]]; then
        echo -e "  ${GREEN}✓ PASS${NC}"
        echo "  Output: ${OUTPUT:0:200}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "  ${RED}✗ FAIL${NC} (exit code: ${EXIT_CODE})"
        echo "  Output: ${OUTPUT:0:200}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test 1: Docker is running
test_step "Docker service" "systemctl is-active --quiet docker"

# Test 2: CoreDNS container is running
test_step "CoreDNS container" "docker ps --filter name=coredns --format '{{.Names}}' | grep -q coredns"

# Test 3: Traefik container is running
test_step "Traefik container" "docker ps --filter name=traefik --format '{{.Names}}' | grep -q traefik"

# Test 4: DNS resolution (aispector.exnada.com)
echo -n "Testing DNS resolution (aispector.exnada.com)... "
DNS_RESULT=$(dig @127.0.0.1 aispector.exnada.com +short +timeout=2 2>/dev/null || echo "")
if [[ -n "${DNS_RESULT}" ]]; then
    echo -e "${GREEN}✓ PASS${NC} (resolves to: ${DNS_RESULT})"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC} (no resolution)"
    ((TESTS_FAILED++))
fi

# Test 5: Backend service is reachable
test_step_with_output "Backend service (vega:8000/health)" "curl -s --max-time 5 http://vega:8000/health"

# Test 6: Traefik routing (localhost with Host header)
echo -n "Testing Traefik routing (localhost with Host header)... "
HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health 2>&1 || echo "000")
if [[ "${HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓ PASS${NC} (HTTP ${HTTP_CODE})"
    RESPONSE=$(curl -s -k --max-time 10 -H "Host: aispector.exnada.com" https://localhost/health)
    echo "  Response: ${RESPONSE:0:100}"
    ((TESTS_PASSED++))
elif [[ "${HTTP_CODE}" == "404" ]]; then
    echo -e "${RED}✗ FAIL${NC} (HTTP 404 - Route not found)"
    echo "  Checking Traefik configuration..."
    docker logs traefik 2>&1 | tail -20 | grep -i "router\|404" || echo "  No relevant logs"
    ((TESTS_FAILED++))
elif [[ "${HTTP_CODE}" == "502" ]] || [[ "${HTTP_CODE}" == "503" ]]; then
    echo -e "${RED}✗ FAIL${NC} (HTTP ${HTTP_CODE} - Backend unreachable)"
    echo "  Checking Traefik logs..."
    docker logs traefik 2>&1 | tail -20 | grep -i "backend\|502\|503" || echo "  No relevant logs"
    ((TESTS_FAILED++))
else
    echo -e "${RED}✗ FAIL${NC} (HTTP ${HTTP_CODE})"
    ((TESTS_FAILED++))
fi

# Test 7: Full HTTPS request (if DNS is configured externally)
echo ""
echo "Testing full HTTPS request (requires external DNS)..."
echo -n "  curl -k https://aispector.exnada.com/health... "
FULL_HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 10 https://aispector.exnada.com/health 2>&1 || echo "000")
if [[ "${FULL_HTTP_CODE}" == "200" ]]; then
    echo -e "${GREEN}✓ PASS${NC} (HTTP ${FULL_HTTP_CODE})"
    FULL_RESPONSE=$(curl -s -k --max-time 10 https://aispector.exnada.com/health)
    echo "  Response: ${FULL_RESPONSE:0:100}"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠ SKIP${NC} (HTTP ${FULL_HTTP_CODE} - may require external DNS configuration)"
    echo "  This test requires DNS to be configured on your client machine"
fi

# Summary
echo ""
echo "============================================================================"
echo "Test Summary"
echo "============================================================================"
echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [[ ${TESTS_FAILED} -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed! Reverse proxy is working.${NC}"
    echo ""
    echo "Final verification:"
    curl -s -k -H "Host: aispector.exnada.com" https://localhost/health
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Please check the errors above.${NC}"
    echo ""
    echo "Debugging steps:"
    echo "1. Check Traefik logs: docker logs traefik"
    echo "2. Check CoreDNS logs: docker logs coredns"
    echo "3. Check backend: curl http://vega:8000/health"
    echo "4. Check DNS: dig @127.0.0.1 aispector.exnada.com"
    echo "5. Check Traefik config: cat /opt/traefik/dynamic.yml"
    exit 1
fi
