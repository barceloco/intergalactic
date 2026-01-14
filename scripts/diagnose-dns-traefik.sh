#!/bin/bash
# Fast diagnostic script for DNS and Traefik issues
# Usage: ./scripts/diagnose-dns-traefik.sh [host]
# Default host: rigel

set -e

HOST=${1:-rigel}

echo "========================================"
echo "DNS and Traefik Diagnostic Report"
echo "Host: ${HOST}"
echo "Timestamp: $(date)"
echo "========================================"

echo ""
echo "=== Checking CoreDNS Service ==="
ssh ${HOST} "systemctl status coredns --no-pager | head -10" || echo "WARNING: CoreDNS service check failed"

echo ""
echo "=== Checking DNS Resolution (from rigel) ==="
echo "mpnas.exnada.com:"
ssh ${HOST} "dig @127.0.0.1 +short mpnas.exnada.com" || echo "ERROR: DNS lookup failed"

echo "aispector.exnada.com:"
ssh ${HOST} "dig @127.0.0.1 +short aispector.exnada.com" || echo "ERROR: DNS lookup failed"

echo "dev.exnada.com:"
ssh ${HOST} "dig @127.0.0.1 +short dev.exnada.com" || echo "ERROR: DNS lookup failed"

echo ""
echo "=== Checking Public DNS (comparison) ==="
echo "aispector.exnada.com from 8.8.8.8:"
ssh ${HOST} "dig @8.8.8.8 +short aispector.exnada.com" || echo "WARNING: Public DNS lookup failed"

echo ""
echo "=== Checking Traefik Service ==="
ssh ${HOST} "systemctl status traefik --no-pager | head -10" || echo "WARNING: Traefik service check failed"

echo ""
echo "=== Checking Traefik Container ==="
ssh ${HOST} "docker ps --filter name=traefik --format 'Container: {{.Names}} | Status: {{.Status}} | Ports: {{.Ports}}'" || echo "WARNING: Docker check failed"

echo ""
echo "=== Recent Traefik Logs (last 30 lines) ==="
ssh ${HOST} "docker logs traefik 2>&1 | tail -30" || echo "WARNING: Unable to fetch logs"

echo ""
echo "=== Checking ACME Certificates ==="
echo "ACME file permissions:"
ssh ${HOST} "ls -lh /opt/traefik/acme.json" || echo "WARNING: acme.json not found"

echo ""
echo "Certificates in storage:"
ssh ${HOST} "cat /opt/traefik/acme.json | jq '.letsencrypt.Certificates[]?.domain // empty' 2>/dev/null || echo 'No certificates found or jq not available'"

echo ""
echo "=== Checking Backend Connectivity ==="
echo "Testing vega:8000/health:"
ssh ${HOST} "curl -s -o /dev/null -w 'HTTP Status: %{http_code} | Time: %{time_total}s\n' --max-time 5 http://vega:8000/health 2>&1 || echo 'FAILED: Cannot connect to vega:8000'"

echo ""
echo "Testing rigel:8000/health (localhost):"
ssh ${HOST} "curl -s -o /dev/null -w 'HTTP Status: %{http_code} | Time: %{time_total}s\n' --max-time 5 http://localhost:8000/health 2>&1 || echo 'FAILED: Cannot connect to localhost:8000'"

echo ""
echo "=== Checking Tailscale Status ==="
ssh ${HOST} "tailscale status | grep -E '(vega|mpnas|rigel)'" || echo "WARNING: Tailscale status check failed"

echo ""
echo "=== Checking Ports Listening ==="
ssh ${HOST} "ss -tlnp | grep -E ':(80|443|53|8000)' | head -20" || echo "WARNING: Port check failed"

echo ""
echo "========================================"
echo "Diagnostic Report Complete"
echo "========================================"
