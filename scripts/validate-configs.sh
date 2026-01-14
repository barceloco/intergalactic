#!/bin/bash
# Pre-deployment configuration validation
# Validates YAML syntax, DNS zone files, and Traefik configuration

set -euo pipefail

ERRORS=0

# Function to report error
error() {
    echo "ERROR: $1"
    ((ERRORS++)) || true
}

# Function to report warning
warning() {
    echo "WARNING: $1"
}

# Validate YAML files
validate_yaml() {
    local file=$1
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import yaml; yaml.safe_load(open('${file}'))" 2>/dev/null; then
            error "Invalid YAML syntax in ${file}"
        fi
    else
        warning "python3 not available, skipping YAML validation for ${file}"
    fi
}

# Validate DNS zone file
validate_zone_file() {
    local zone_file=$1
    if [ -f "${zone_file}" ]; then
        # Basic zone file validation
        if ! grep -q "SOA" "${zone_file}" 2>/dev/null; then
            error "Zone file ${zone_file} missing SOA record"
        fi
        if ! grep -q "NS" "${zone_file}" 2>/dev/null; then
            error "Zone file ${zone_file} missing NS record"
        fi
    else
        error "Zone file not found: ${zone_file}"
    fi
}

# Validate Traefik configuration
validate_traefik_config() {
    local config_file=$1
    if [ -f "${config_file}" ]; then
        validate_yaml "${config_file}"
        # Check for required sections
        if ! grep -q "entryPoints" "${config_file}" 2>/dev/null && \
           ! grep -q "entrypoints" "${config_file}" 2>/dev/null; then
            warning "Traefik config ${config_file} may be missing entryPoints"
        fi
    else
        error "Traefik config not found: ${config_file}"
    fi
}

echo "Validating configurations..."

# Validate CoreDNS configuration
if [ -f "/opt/coredns/Corefile" ]; then
    echo "Validating CoreDNS Corefile..."
    # Basic syntax check
    if ! grep -q ":" /opt/coredns/Corefile 2>/dev/null; then
        error "Corefile may be invalid"
    fi
else
    warning "Corefile not found (may not be deployed yet)"
fi

# Validate DNS zone file
if [ -f "/opt/coredns/db.exnada.com" ]; then
    echo "Validating DNS zone file..."
    validate_zone_file "/opt/coredns/db.exnada.com"
fi

# Validate Traefik configuration
if [ -f "/opt/traefik/traefik.yml" ]; then
    echo "Validating Traefik static config..."
    validate_traefik_config "/opt/traefik/traefik.yml"
fi

if [ -f "/opt/traefik/dynamic.yml" ]; then
    echo "Validating Traefik dynamic config..."
    validate_traefik_config "/opt/traefik/dynamic.yml"
fi

# Validate docker-compose files
for compose_file in /opt/coredns/docker-compose.yml /opt/traefik/docker-compose.yml; do
    if [ -f "${compose_file}" ]; then
        echo "Validating docker-compose: ${compose_file}"
        validate_yaml "${compose_file}"
    fi
done

# Summary
if [ ${ERRORS} -eq 0 ]; then
    echo "✓ All validations passed"
    exit 0
else
    echo "✗ ${ERRORS} validation error(s) found"
    exit 1
fi
