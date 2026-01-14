#!/bin/bash
# Alert checking script for intergalactic infrastructure
# Checks for conditions that require alerting

set -euo pipefail

ALERTS=0

# Function to send alert (placeholder - implement actual notification)
send_alert() {
    local severity=$1
    local message=$2
    echo "[${severity}] ${message}"
    ((ALERTS++)) || true
    # TODO: Implement actual alerting (email, webhook, etc.)
}

# Check container status
check_containers() {
    if ! docker ps --filter name=coredns --format "{{.Names}}" | grep -q coredns; then
        send_alert "CRITICAL" "CoreDNS container is not running"
    fi
    
    if ! docker ps --filter name=traefik --format "{{.Names}}" | grep -q traefik; then
        send_alert "CRITICAL" "Traefik container is not running"
    fi
}

# Check systemd services
check_systemd_services() {
    if ! systemctl is-active --quiet coredns.service 2>/dev/null; then
        send_alert "CRITICAL" "CoreDNS systemd service is not active"
    fi
    
    if ! systemctl is-active --quiet traefik.service 2>/dev/null; then
        send_alert "CRITICAL" "Traefik systemd service is not active"
    fi
}

# Check certificate expiration
check_certificates() {
    local test_host="${TEST_HOST:-aispector.exnada.com}"
    
    if command -v openssl >/dev/null 2>&1; then
        local cert_info=$(echo | openssl s_client -connect "${test_host}:443" -servername "${test_host}" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null || echo "")
        
        if [ -n "${cert_info}" ]; then
            local not_after=$(echo "${cert_info}" | grep "notAfter" | cut -d= -f2)
            if [ -n "${not_after}" ]; then
                local expiry_date=$(date -d "${not_after}" +%s 2>/dev/null || echo "0")
                local current_date=$(date +%s)
                local days_until_expiry=$(( (expiry_date - current_date) / 86400 ))
                
                if [ ${days_until_expiry} -lt 0 ]; then
                    send_alert "CRITICAL" "Certificate for ${test_host} has expired"
                elif [ ${days_until_expiry} -lt 30 ]; then
                    send_alert "WARNING" "Certificate for ${test_host} expires in ${days_until_expiry} days"
                fi
            fi
        fi
    fi
}

# Check health endpoints
check_health_endpoints() {
    local test_host="${TEST_HOST:-aispector.exnada.com}"
    local health_path="${HEALTH_PATH:-/health}"
    
    if command -v curl >/dev/null 2>&1; then
        local http_code=$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 5 -H "Host: ${test_host}" "https://localhost${health_path}" 2>/dev/null || echo "000")
        
        if [ "${http_code}" = "000" ]; then
            send_alert "WARNING" "Health endpoint for ${test_host} is not accessible"
        elif [ "${http_code}" = "503" ]; then
            send_alert "WARNING" "Backend for ${test_host} is returning 503 (unavailable)"
        fi
    fi
}

# Check disk space
check_disk_space() {
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "${disk_usage}" -gt 90 ]; then
        send_alert "CRITICAL" "Disk usage is at ${disk_usage}%"
    elif [ "${disk_usage}" -gt 80 ]; then
        send_alert "WARNING" "Disk usage is at ${disk_usage}%"
    fi
}

# Run all checks
check_containers
check_systemd_services
check_certificates
check_health_endpoints
check_disk_space

# Exit with appropriate code
if [ ${ALERTS} -gt 0 ]; then
    exit 1
else
    exit 0
fi
