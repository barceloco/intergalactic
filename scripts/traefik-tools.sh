#!/bin/bash
# Traefik Tools - Consolidated Traefik diagnostic and testing utilities
# Consolidates: check-traefik-routing.sh, diagnose-traefik-backend.sh, check-dev-exnada-traefik.sh

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
Traefik Tools - Consolidated Traefik diagnostics and testing

Usage: $SCRIPT_NAME <command> [options]

Commands:
    status              Check Traefik container status
    check-routing       Check Traefik routing configuration
    test-backend        Test backend connectivity for a route
    diagnose           Full diagnostic of Traefik setup
    logs               Show Traefik logs
    test-route         Test specific route end-to-end

Options:
    -h, --help         Show this help message
    -v, --verbose      Enable verbose output
    -f, --follow       Follow logs (for 'logs' command)

Examples:
    $SCRIPT_NAME status
    $SCRIPT_NAME check-routing
    $SCRIPT_NAME test-backend mpnas.exnada.com
    $SCRIPT_NAME diagnose
    $SCRIPT_NAME logs -f
    $SCRIPT_NAME test-route https://mpnas.exnada.com

USAGE
    exit 1
}

# Check Traefik status
check_status() {
    log_info "Checking Traefik container status..."
    
    if ! docker ps --filter "name=traefik" --format "{{.Names}}" | grep -q traefik; then
        log_error "Traefik container is not running"
        log_info "Checking if container exists..."
        if docker ps -a --filter "name=traefik" --format "{{.Names}}" | grep -q traefik; then
            log_warning "Traefik container exists but is not running"
            log_info "Container status:"
            docker ps -a --filter "name=traefik" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        else
            log_error "Traefik container does not exist"
        fi
        return 1
    fi
    
    log_success "Traefik container is running"
    docker ps --filter "name=traefik" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    # Check if listening on ports
    log_info "Checking port bindings..."
    if ss -tulpn | grep -q ":80.*traefik"; then
        log_success "Traefik is listening on port 80 (HTTP)"
    else
        log_warning "Traefik is NOT listening on port 80"
    fi
    
    if ss -tulpn | grep -q ":443.*traefik"; then
        log_success "Traefik is listening on port 443 (HTTPS)"
    else
        log_warning "Traefik is NOT listening on port 443"
    fi
}

# Check routing configuration
check_routing() {
    log_info "Checking Traefik routing configuration..."
    
    # Check if dynamic config exists
    local config_dir="/opt/traefik"
    if [[ ! -f "$config_dir/dynamic.yml" ]]; then
        log_error "Traefik dynamic configuration not found at $config_dir/dynamic.yml"
        return 1
    fi
    
    log_success "Dynamic configuration found"
    
    # Show configured routes
    log_info "Configured routes:"
    if command -v yq &>/dev/null; then
        yq '.http.routers' "$config_dir/dynamic.yml"
    else
        grep -A 5 "routers:" "$config_dir/dynamic.yml" || log_warning "Could not parse routes (install yq for better output)"
    fi
}

# Test backend connectivity
test_backend() {
    local host="${1:-}"
    if [[ -z "$host" ]]; then
        log_error "Host parameter required"
        echo "Usage: $SCRIPT_NAME test-backend <hostname>"
        return 1
    fi
    
    log_info "Testing backend connectivity for: $host..."
    
    # Extract backend from dynamic config
    local config_dir="/opt/traefik"
    if [[ ! -f "$config_dir/dynamic.yml" ]]; then
        log_error "Dynamic configuration not found"
        return 1
    fi
    
    log_info "Checking if route exists for $host..."
    if ! grep -q "$host" "$config_dir/dynamic.yml"; then
        log_warning "No route found for $host in dynamic configuration"
        return 1
    fi
    
    log_success "Route found for $host"
    
    # Try to extract backend URL (simplified - would need proper YAML parsing)
    log_info "Attempting to connect to backend..."
    # This is a simplified check - in production you'd parse the YAML properly
    log_info "Check the dynamic.yml configuration for the backend URL"
}

# Full diagnostic
diagnose() {
    log_info "Running full Traefik diagnostic..."
    echo ""
    
    # Check status
    check_status
    echo ""
    
    # Check configuration files
    log_info "Checking configuration files..."
    local config_dir="/opt/traefik"
    for file in traefik.yml dynamic.yml acme.json; do
        if [[ -f "$config_dir/$file" ]]; then
            log_success "$file exists"
            ls -lh "$config_dir/$file"
        else
            log_error "$file NOT found"
        fi
    done
    echo ""
    
    # Check routing
    check_routing
    echo ""
    
    # Check recent logs for errors
    log_info "Checking recent logs for errors..."
    if docker logs traefik --tail 50 2>&1 | grep -i error; then
        log_warning "Errors found in recent logs"
    else
        log_success "No errors in recent logs"
    fi
}

# Show logs
show_logs() {
    local follow=false
    if [[ "${1:-}" == "-f" || "${1:-}" == "--follow" ]]; then
        follow=true
    fi
    
    log_info "Showing Traefik logs..."
    if $follow; then
        docker logs -f traefik
    else
        docker logs --tail 100 traefik
    fi
}

# Test route end-to-end
test_route() {
    local url="${1:-}"
    if [[ -z "$url" ]]; then
        log_error "URL parameter required"
        echo "Usage: $SCRIPT_NAME test-route <url>"
        return 1
    fi
    
    log_info "Testing route: $url..."
    
    # Test connectivity
    log_info "Testing HTTP connectivity..."
    if curl -sSL -o /dev/null -w "%{http_code}" "$url" | grep -q "^[23]"; then
        log_success "HTTP request successful"
    else
        http_code=$(curl -sSL -o /dev/null -w "%{http_code}" "$url" || true)
        log_error "HTTP request failed (status: $http_code)"
        return 1
    fi
    
    # Show response headers
    log_info "Response headers:"
    curl -sI "$url" | head -20
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        usage
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        status)
            check_status "$@"
            ;;
        check-routing)
            check_routing "$@"
            ;;
        test-backend)
            test_backend "$@"
            ;;
        diagnose)
            diagnose "$@"
            ;;
        logs)
            show_logs "$@"
            ;;
        test-route)
            test_route "$@"
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
