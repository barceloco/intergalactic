#!/usr/bin/env bash
# Diagnose reverse proxy infrastructure issues
# Usage: ./scripts/diagnose-reverse-proxy.sh [rigel-ip-or-hostname]

set -euo pipefail

HOST="${1:-rigel}"
SSH_KEY="${SSH_KEY:-~/.ssh/intergalactic_ansible}"

echo "============================================================================"
echo "Diagnosing Reverse Proxy Infrastructure on ${HOST}"
echo "============================================================================"
echo ""

echo "[1] Checking if roles were enabled..."
ssh -i "${SSH_KEY}" ansible@${HOST} "grep -E 'internal_dns_enabled|edge_ingress_enabled' /etc/ansible/facts.d/*.fact 2>/dev/null || echo 'No facts found. Checking host_vars...'"
echo ""

echo "[2] Checking if docker-compose files exist..."
ssh -i "${SSH_KEY}" ansible@${HOST} "ls -la /opt/coredns/docker-compose.yml 2>&1 || echo 'CoreDNS compose file not found'"
ssh -i "${SSH_KEY}" ansible@${HOST} "ls -la /opt/traefik/docker-compose.yml 2>&1 || echo 'Traefik compose file not found'"
echo ""

echo "[3] Checking if data directories exist..."
ssh -i "${SSH_KEY}" ansible@${HOST} "ls -la /opt/coredns/ 2>&1 | head -10"
ssh -i "${SSH_KEY}" ansible@${HOST} "ls -la /opt/traefik/ 2>&1 | head -10"
echo ""

echo "[4] Checking all containers (including stopped)..."
ssh -i "${SSH_KEY}" ansible@${HOST} "docker ps -a | grep -E 'coredns|traefik' || echo 'No coredns or traefik containers found'"
echo ""

echo "[5] Trying to start containers manually..."
echo "CoreDNS:"
ssh -i "${SSH_KEY}" ansible@${HOST} "cd /opt/coredns && docker compose up -d 2>&1 || echo 'Failed to start CoreDNS'"
echo ""
echo "Traefik:"
ssh -i "${SSH_KEY}" ansible@${HOST} "cd /opt/traefik && docker compose up -d 2>&1 || echo 'Failed to start Traefik'"
echo ""

echo "[6] Checking container status after manual start..."
ssh -i "${SSH_KEY}" ansible@${HOST} "docker ps | grep -E 'coredns|traefik' || echo 'Containers still not running'"
echo ""

echo "[7] Checking for port conflicts..."
ssh -i "${SSH_KEY}" ansible@${HOST} "sudo netstat -tuln | grep -E ':(53|80|443)' || echo 'No processes on ports 53, 80, 443'"
echo ""

echo "[8] Checking Docker service status..."
ssh -i "${SSH_KEY}" ansible@${HOST} "systemctl status docker --no-pager | head -5"
echo ""

echo "============================================================================"
echo "If containers don't exist, the roles may not have run."
echo "Check the Ansible playbook output for errors or skipped tasks."
echo "============================================================================"
