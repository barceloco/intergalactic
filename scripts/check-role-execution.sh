#!/usr/bin/env bash
# Check if reverse proxy roles actually executed
# Usage: ./scripts/check-role-execution.sh [rigel-ip-or-hostname]

set -euo pipefail

HOST="${1:-rigel}"
SSH_KEY="${SSH_KEY:-~/.ssh/intergalactic_ansible}"

echo "============================================================================"
echo "Checking Role Execution Status"
echo "============================================================================"
echo ""

echo "[1] Checking ansible user docker group membership..."
ssh -i "${SSH_KEY}" ansible@${HOST} "groups"
ssh -i "${SSH_KEY}" ansible@${HOST} "id ansible"
echo ""

echo "[2] Testing ansible user docker access..."
ssh -i "${SSH_KEY}" ansible@${HOST} "docker ps 2>&1 | head -3"
echo ""

echo "[3] Checking if variables are set correctly..."
ssh -i "${SSH_KEY}" ansible@${HOST} "sudo cat /etc/ansible/facts.d/*.fact 2>/dev/null | grep -E 'internal_dns|edge_ingress' || echo 'No facts found'"
echo ""

echo "[4] Checking host_vars file..."
ssh -i "${SSH_KEY}" ansible@${HOST} "sudo cat /etc/ansible/host_vars/rigel.yml 2>/dev/null | grep -E 'internal_dns_enabled|edge_ingress_enabled' || echo 'Host vars file not found on remote'"
echo ""

echo "[5] Checking if roles exist in playbook..."
echo "Run this locally:"
echo "  grep -A 20 'roles:' ansible/playbooks/rigel.yml | grep -E 'internal_dns|edge_ingress'"
echo ""

echo "============================================================================"
echo "Next Steps:"
echo "============================================================================"
echo "1. Re-run the playbook with verbose output:"
echo "   ./scripts/run-ansible.sh prod rigel -vv"
echo ""
echo "2. Check if roles were skipped in the output (look for 'Skipping internal_dns role')"
echo ""
echo "3. If roles were skipped, verify variables are set:"
echo "   - internal_dns_enabled: true"
echo "   - edge_ingress_enabled: true"
echo "   in ansible/inventories/prod/host_vars/rigel.yml"
echo ""
echo "============================================================================"
