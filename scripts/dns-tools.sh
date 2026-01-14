#!/bin/bash
# DNS Tools - Consolidated DNS diagnostic and testing utilities
# Consolidates: check-dns-nameservers.sh, test-coredns-config.sh, validate-coredns-split-dns.sh,
#               test-dns-record-creation.sh, check-acme-dns-records.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Show usage
usage() {
    cat << USAGE
DNS Tools - Consolidated DNS diagnostics and testing

Usage: $SCRIPT_NAME <command> [options]

Commands:
    check-nameservers    Check DNS nameserver configuration
    test-coredns        Test CoreDNS configuration
    validate-split-dns  Validate split-horizon DNS setup
    test-resolution     Test DNS resolution for specific host
    check-acme-records  Check ACME DNS records

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output

Examples:
    $SCRIPT_NAME check-nameservers
    $SCRIPT_NAME test-coredns
    $SCRIPT_NAME validate-split-dns
    $SCRIPT_NAME test-resolution mpnas.exnada.com
    $SCRIPT_NAME check-acme-records

USAGE
    exit 1
}

# Check DNS nameservers
check_nameservers() {
    log_info "Checking DNS nameserver configuration..."
    
    if [[ ! -f /etc/resolv.conf ]]; then
        log_error "/etc/resolv.conf not found"
        return 1
    fi
    
    log_info "Current nameservers:"
    grep "^nameserver" /etc/resolv.conf || log_warning "No nameservers configured"
    
    log_info "Testing nameserver connectivity..."
    while read -r line; do
        if [[ $line =~ ^nameserver[[:space:]]+([0-9.]+) ]]; then
            nameserver="${BASH_REMATCH[1]}"
            if timeout 2 ping -c 1 "$nameserver" &>/dev/null; then
                log_success "Nameserver $nameserver is reachable"
            else
                log_warning "Nameserver $nameserver is NOT reachable"
            fi
        fi
    done < /etc/resolv.conf
}

# Test CoreDNS configuration
test_coredns() {
    log_info "Testing CoreDNS configuration..."
    
    # Check if CoreDNS is running
    if ! docker ps | grep -q coredns; then
        log_error "CoreDNS container is not running"
        return 1
    fi
    
    log_success "CoreDNS container is running"
    
    # Check if CoreDNS is listening on port 53
    if ss -tulpn | grep -q ":53.*coredns"; then
        log_success "CoreDNS is listening on port 53"
    else
        log_warning "CoreDNS may not be listening on port 53"
    fi
    
    # Test DNS resolution
    log_info "Testing DNS resolution via CoreDNS..."
    if dig @127.0.0.1 google.com +short &>/dev/null; then
        log_success "DNS resolution is working"
    else
        log_error "DNS resolution failed"
        return 1
    fi
}

# Validate split-horizon DNS
validate_split_dns() {
    local internal_domain="${1:-exnada.com}"
    log_info "Validating split-horizon DNS for domain: $internal_domain..."
    
    # Test internal resolution
    log_info "Testing internal domain resolution..."
    if dig @127.0.0.1 "$internal_domain" +short &>/dev/null; then
        log_success "Internal domain $internal_domain resolves"
    else
        log_warning "Internal domain $internal_domain does not resolve"
    fi
    
    # Test external resolution
    log_info "Testing external domain resolution..."
    if dig @127.0.0.1 google.com +short &>/dev/null; then
        log_success "External domains resolve (forwarding works)"
    else
        log_error "External domain resolution failed"
        return 1
    fi
}

# Test DNS resolution for specific host
test_resolution() {
    local host="${1:-}"
    if [[ -z "$host" ]]; then
        log_error "Host parameter required"
        echo "Usage: $SCRIPT_NAME test-resolution <hostname>"
        return 1
    fi
    
    log_info "Testing DNS resolution for: $host"
    
    # Test with system resolver
    log_info "Testing with system resolver..."
    if dig "$host" +short; then
        log_success "Resolution successful (system resolver)"
    else
        log_warning "Resolution failed (system resolver)"
    fi
    
    # Test with CoreDNS directly
    log_info "Testing with CoreDNS (127.0.0.1)..."
    if dig @127.0.0.1 "$host" +short; then
        log_success "Resolution successful (CoreDNS)"
    else
        log_warning "Resolution failed (CoreDNS)"
    fi
    
    # Show full DNS query
    log_info "Full DNS query:"
    dig @127.0.0.1 "$host"
}

# Check ACME DNS records
check_acme_records() {
    local domain="${1:-exnada.com}"
    log_info "Checking ACME DNS records for domain: $domain..."
    
    # Check for _acme-challenge records
    log_info "Checking for _acme-challenge TXT records..."
    dig "_acme-challenge.$domain" TXT +short | grep -q . && log_success "Found ACME challenge records" || log_info "No ACME challenge records found (this is normal if not currently validating)"
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        usage
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        check-nameservers)
            check_nameservers "$@"
            ;;
        test-coredns)
            test_coredns "$@"
            ;;
        validate-split-dns)
            validate_split_dns "$@"
            ;;
        test-resolution)
            test_resolution "$@"
            ;;
        check-acme-records)
            check_acme_records "$@"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            ;;
    esac
}

main "$@"
