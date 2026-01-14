#!/bin/bash
# Metrics collection script for intergalactic infrastructure
# Collects metrics for DNS, Traefik, Docker, and system resources

set -euo pipefail

METRICS_DIR="${METRICS_DIR:-/var/log/metrics}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create metrics directory if it doesn't exist
mkdir -p "${METRICS_DIR}"

# Function to collect DNS metrics
collect_dns_metrics() {
    local output_file="${METRICS_DIR}/dns-${TIMESTAMP}.json"
    
    # DNS query rate (queries per second estimate)
    local dns_queries=0
    if command -v dig >/dev/null 2>&1; then
        # Count DNS queries in last minute (approximate)
        dns_queries=$(journalctl -u coredns --since "1 minute ago" --no-pager | grep -c "query" || echo "0")
    fi
    
    # DNS response time
    local dns_latency=0
    if command -v dig >/dev/null 2>&1; then
        local start=$(date +%s%N)
        dig @127.0.0.1 +timeout=2 exnada.com >/dev/null 2>&1 && true
        local end=$(date +%s%N)
        dns_latency=$(( (end - start) / 1000000 ))  # Convert to milliseconds
    fi
    
    cat > "${output_file}" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "service": "coredns",
  "metrics": {
    "queries_per_minute": ${dns_queries},
    "response_time_ms": ${dns_latency},
    "container_running": $(docker ps --filter name=coredns --format "{{.Names}}" | grep -q coredns && echo "true" || echo "false")
  }
}
EOF
}

# Function to collect Traefik metrics
collect_traefik_metrics() {
    local output_file="${METRICS_DIR}/traefik-${TIMESTAMP}.json"
    
    # Traefik request rate (approximate)
    local traefik_requests=0
    if docker ps --filter name=traefik --format "{{.Names}}" | grep -q traefik; then
        traefik_requests=$(docker logs traefik --since 1m 2>&1 | grep -c "request" || echo "0")
    fi
    
    # Traefik container status
    local traefik_running=false
    if docker ps --filter name=traefik --format "{{.Names}}" | grep -q traefik; then
        traefik_running=true
    fi
    
    cat > "${output_file}" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "service": "traefik",
  "metrics": {
    "requests_per_minute": ${traefik_requests},
    "container_running": ${traefik_running}
  }
}
EOF
}

# Function to collect Docker metrics
collect_docker_metrics() {
    local output_file="${METRICS_DIR}/docker-${TIMESTAMP}.json"
    
    # Docker daemon status
    local docker_running=false
    if docker info >/dev/null 2>&1; then
        docker_running=true
    fi
    
    # Container count
    local container_count=0
    if ${docker_running}; then
        container_count=$(docker ps -q | wc -l)
    fi
    
    cat > "${output_file}" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "service": "docker",
  "metrics": {
    "daemon_running": ${docker_running},
    "container_count": ${container_count}
  }
}
EOF
}

# Function to collect system metrics
collect_system_metrics() {
    local output_file="${METRICS_DIR}/system-${TIMESTAMP}.json"
    
    # CPU usage
    local cpu_usage=0
    if command -v top >/dev/null 2>&1; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    fi
    
    # Memory usage
    local mem_total=0
    local mem_used=0
    if [ -f /proc/meminfo ]; then
        mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_used=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        mem_used=$((mem_total - mem_used))
    fi
    
    # Disk usage
    local disk_usage=0
    if command -v df >/dev/null 2>&1; then
        disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    fi
    
    cat > "${output_file}" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "service": "system",
  "metrics": {
    "cpu_usage_percent": ${cpu_usage},
    "memory_total_kb": ${mem_total},
    "memory_used_kb": ${mem_used},
    "disk_usage_percent": ${disk_usage}
  }
}
EOF
}

# Collect all metrics
collect_dns_metrics
collect_traefik_metrics
collect_docker_metrics
collect_system_metrics

# Clean up old metrics (keep last 24 hours)
find "${METRICS_DIR}" -name "*.json" -mtime +1 -delete

echo "Metrics collected: ${TIMESTAMP}"
