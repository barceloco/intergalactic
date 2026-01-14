#!/bin/bash
# Unified health check script for intergalactic infrastructure
# Checks: CoreDNS, Traefik, Docker, Tailscale, Backend services

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Exit codes
EXIT_SUCCESS=0
EXIT_FAILURE=1
EXIT_WARNING=2

# Track overall health
OVERALL_HEALTH=true
WARNINGS=0
FAILURES=0

# Function to print status
print_status() {
    local status=$1
    local service=$2
    local message=$3
    
    case $status in
        "OK")
            echo -e "${GREEN}✓${NC} ${service}: ${message}"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠${NC} ${service}: ${message}"
            OVERALL_HEALTH=false
            ((WARNINGS++)) || true
            ;;
        "FAIL")
            echo -e "${RED}✗${NC} ${service}: ${message}"
            OVERALL_HEALTH=false
            ((FAILURES++)) || true
            ;;
    esac
}

# Check Docker daemon
check_docker() {
    if docker info >/dev/null 2>&1; then
        print_status "OK" "Docker" "Daemon is running"
        return 0
    else
        print_status "FAIL" "Docker" "Daemon is not running or not accessible"
        return 1
    fi
}

# Check Tailscale connectivity
check_tailscale() {
    if command -v tailscale >/dev/null 2>&1; then
        if tailscale status >/dev/null 2>&1; then
            local ip=$(tailscale ip -4 2>/dev/null || echo "")
            if [[ -n "$ip" ]]; then
                print_status "OK" "Tailscale" "Connected (IP: ${ip})"
                return 0
            else
                print_status "WARN" "Tailscale" "Connected but no IPv4 address"
                return 1
            fi
        else
            print_status "FAIL" "Tailscale" "Not connected"
            return 1
        fi
    else
        print_status "WARN" "Tailscale" "Not installed"
        return 1
    fi
}

# Check CoreDNS
check_coredns() {
    # Check if container is running
    if docker ps --filter name=coredns --format "{{.Names}}" | grep -q "^coredns$"; then
        # Check if DNS is responding
        if dig @127.0.0.1 +timeout=2 +tries=1 exnada.com >/dev/null 2>&1; then
            print_status "OK" "CoreDNS" "Container running and DNS responding"
            return 0
        else
            print_status "WARN" "CoreDNS" "Container running but DNS not responding"
            return 1
        fi
    else
        print_status "FAIL" "CoreDNS" "Container is not running"
        return 1
    fi
}

# Check Traefik
check_traefik() {
    # Check if container is running
    if docker ps --filter name=traefik --format "{{.Names}}" | grep -q "^traefik$"; then
        # Check if API is responding (if enabled)
        if curl -sf http://localhost:8080/ping >/dev/null 2>&1 || curl -sfk https://localhost/ping >/dev/null 2>&1; then
            print_status "OK" "Traefik" "Container running and API responding"
            return 0
        else
            # Container might be running but API not accessible (could be normal if API is disabled)
            print_status "WARN" "Traefik" "Container running but API not accessible"
            return 1
        fi
    else
        print_status "FAIL" "Traefik" "Container is not running"
        return 1
    fi
}

# Check backend service health
check_backend() {
    local host=$1
    local port=${2:-8000}
    local health_path=${3:-/health}
    
    local url="http://${host}:${port}${health_path}"
    
    if curl -sf --max-time 5 "${url}" >/dev/null 2>&1; then
        print_status "OK" "Backend (${host}:${port})" "Health check passed"
        return 0
    else
        print_status "FAIL" "Backend (${host}:${port})" "Health check failed"
        return 1
    fi
}

# Check systemd service
check_systemd_service() {
    local service=$1
    
    if systemctl is-active --quiet "${service}"; then
        print_status "OK" "Systemd (${service})" "Service is active"
        return 0
    else
        print_status "FAIL" "Systemd (${service})" "Service is not active"
        return 1
    fi
}

# Main execution
main() {
    echo "============================================================================"
    echo "Intergalactic Infrastructure Health Check"
    echo "============================================================================"
    echo ""
    
    # Core infrastructure checks
    check_docker
    check_tailscale
    
    echo ""
    echo "--- Service Checks ---"
    
    # Check CoreDNS if enabled
    if systemctl list-unit-files | grep -q "^coredns.service"; then
        check_systemd_service "coredns"
        check_coredns
    fi
    
    # Check Traefik if enabled
    if systemctl list-unit-files | grep -q "^traefik.service"; then
        check_systemd_service "traefik"
        check_traefik
    fi
    
    echo ""
    echo "============================================================================"
    echo "Summary"
    echo "============================================================================"
    
    if $OVERALL_HEALTH; then
        echo -e "${GREEN}✓ All checks passed${NC}"
        exit $EXIT_SUCCESS
    else
        echo -e "${RED}✗ Health check failed${NC}"
        echo "  Failures: ${FAILURES}"
        echo "  Warnings: ${WARNINGS}"
        exit $EXIT_FAILURE
    fi
}

# Run main function
main "$@"
