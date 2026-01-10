#!/usr/bin/env bash
# Verify reverse proxy infrastructure (CoreDNS + Traefik) on rigel
# Usage: ./scripts/verify-reverse-proxy.sh [rigel-ip-or-hostname]

set -euo pipefail

HOST="${1:-rigel}"
SSH_KEY="${SSH_KEY:-~/.ssh/intergalactic_ansible}"

echo "============================================================================"
echo "Verifying Reverse Proxy Infrastructure on ${HOST}"
echo "============================================================================"
echo ""

echo "[1/8] Checking CoreDNS container status..."
ssh -i "${SSH_KEY}" ansible@${HOST} "docker ps --filter name=coredns --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
echo ""

echo "[2/8] Checking Traefik container status..."
ssh -i "${SSH_KEY}" ansible@${HOST} "docker ps --filter name=traefik --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
echo ""

echo "[3/8] Checking CoreDNS logs (last 10 lines)..."
ssh -i "${SSH_KEY}" ansible@${HOST} "docker logs --tail 10 coredns 2>&1 | tail -10"
echo ""

echo "[4/8] Checking Traefik logs (last 10 lines)..."
ssh -i "${SSH_KEY}" ansible@${HOST} "docker logs --tail 10 traefik 2>&1 | tail -10"
echo ""

echo "[5/8] Testing DNS resolution from rigel (should resolve to Tailscale IP)..."
TAILSCALE_IP=$(ssh -i "${SSH_KEY}" ansible@${HOST} "tailscale ip -4")
echo "Tailscale IP: ${TAILSCALE_IP}"
echo ""
ssh -i "${SSH_KEY}" ansible@${HOST} "dig @127.0.0.1 mpnas.company.com +short"
ssh -i "${SSH_KEY}" ansible@${HOST} "dig @127.0.0.1 aispector.company.com +short"
ssh -i "${SSH_KEY}" ansible@${HOST} "dig @127.0.0.1 dev.company.com +short"
echo ""

echo "[6/8] Testing DNS forwarding (should resolve to public IP)..."
ssh -i "${SSH_KEY}" ansible@${HOST} "dig @127.0.0.1 www.company.com +short"
echo ""

echo "[7/8] Checking firewall rules for tailscale0 interface..."
ssh -i "${SSH_KEY}" ansible@${HOST} "sudo nft list ruleset | grep -A 2 'tailscale0' | head -20"
echo ""

echo "[8/8] Testing Traefik HTTP redirect (should redirect to HTTPS)..."
echo "Testing: http://${HOST}/"
curl -v -L --max-redirs 3 "http://${HOST}/" 2>&1 | grep -E "(HTTP|Location|301|302)" || echo "Note: This requires Tailscale access to ${HOST}"
echo ""

echo "============================================================================"
echo "Manual Testing Steps:"
echo "============================================================================"
echo ""
echo "1. Test DNS resolution (from a machine with Tailscale Split DNS configured):"
echo "   dig mpnas.company.com"
echo "   dig aispector.company.com"
echo "   dig dev.company.com"
echo ""
echo "2. Test HTTPS routing (from a machine with Tailscale access):"
echo "   curl -k https://mpnas.company.com/health"
echo "   curl -k https://aispector.company.com/health"
echo "   curl -k https://dev.company.com/health"
echo ""
echo "3. Check Traefik dashboard (internal only, not exposed):"
echo "   ssh ansible@${HOST} 'docker exec traefik wget -qO- http://localhost:8080/api/rawdata | jq .'"
echo ""
echo "4. Check ACME certificate status:"
echo "   ssh ansible@${HOST} 'sudo cat /opt/traefik/acme.json | jq .letsencrypt.Certificates'"
echo ""
echo "============================================================================"
