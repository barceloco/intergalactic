#!/bin/bash
# Fast Traefik config update without full playbook run
# Usage: ./scripts/quick-deploy-traefik.sh [host]
# Default host: rigel

set -e

HOST=${1:-rigel}

echo "========================================"
echo "Quick Traefik Deployment"
echo "Host: ${HOST}"
echo "Timestamp: $(date)"
echo "========================================"

echo ""
echo "=== Deploying Traefik configuration to ${HOST} ==="

# Run only edge_ingress tasks with tags
./scripts/run-ansible.sh prod ${HOST} production \
  --tags "edge_ingress" \
  --skip-tags "validate"

echo ""
echo "=== Restarting Traefik service ==="
ssh ${HOST} "sudo systemctl restart traefik"

echo ""
echo "=== Waiting for Traefik to start ==="
sleep 5

echo ""
echo "=== Checking Traefik status ==="
ssh ${HOST} "systemctl status traefik --no-pager | head -15"

echo ""
echo "=== Recent Traefik logs ==="
ssh ${HOST} "docker logs traefik 2>&1 | tail -20"

echo ""
echo "========================================"
echo "Deployment Complete"
echo "========================================"
echo ""
echo "To watch Traefik logs in real-time:"
echo "  ssh ${HOST} 'docker logs -f traefik'"
echo ""
echo "To check ACME certificate issuance:"
echo "  ssh ${HOST} \"docker logs traefik 2>&1 | grep -i 'certificate obtained'\""
echo ""
