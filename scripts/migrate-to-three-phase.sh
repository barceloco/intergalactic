#!/usr/bin/env bash
# Migrate existing hosts to three-phase structure
# Usage: ./scripts/migrate-to-three-phase.sh <host> [tailscale-hostname]

set -euo pipefail

HOST="${1:-}"
TAILSCALE_HOSTNAME="${2:-}"

if [[ -z "${HOST}" ]]; then
  echo "ERROR: Host name is required"
  echo ""
  echo "Usage: ./scripts/migrate-to-three-phase.sh <host> [tailscale-hostname]"
  exit 1
fi

SSH_KEY="${SSH_KEY:-~/.ssh/intergalactic_ansible}"

echo "============================================================================"
echo "Migrating ${HOST} to Three-Phase Structure"
echo "============================================================================"
echo ""

echo "[1/5] Checking host accessibility..."
if ssh -i "${SSH_KEY}" -o ConnectTimeout=5 ansible@${HOST} "echo 'Connected'" 2>/dev/null; then
  echo "✓ Host is accessible"
else
  echo "✗ ERROR: Cannot connect to ${HOST}"
  exit 1
fi

echo ""
echo "[2/5] Checking Tailscale status..."
TAILSCALE_STATUS=$(ssh -i "${SSH_KEY}" ansible@${HOST} "tailscale status 2>&1" || echo "NOT_INSTALLED")

if echo "${TAILSCALE_STATUS}" | grep -q "NOT_INSTALLED\|command not found"; then
  echo "✗ Tailscale is not installed"
  echo "Run: ./scripts/run-ansible.sh prod ${HOST} foundation"
  exit 1
fi

echo "✓ Tailscale is installed and connected"

echo ""
echo "[3/5] Getting Tailscale hostname..."
if [[ -z "${TAILSCALE_HOSTNAME}" ]]; then
  TAILSCALE_HOSTNAME=$(ssh -i "${SSH_KEY}" ansible@${HOST} "tailscale status --json | python3 -c \"import sys, json; data = json.load(sys.stdin); print(data.get('Self', {}).get('DNSName', ''))\" 2>/dev/null" || echo "")
  
  if [[ -z "${TAILSCALE_HOSTNAME}" ]]; then
    echo "✗ Could not automatically detect Tailscale hostname"
    echo "Run: tailscale status | grep ${HOST}"
    exit 1
  fi
fi

echo "✓ Tailscale hostname: ${TAILSCALE_HOSTNAME}"

echo ""
echo "[4/5] Testing Tailscale connectivity..."
if ssh -i "${SSH_KEY}" -o ConnectTimeout=5 ansible@${TAILSCALE_HOSTNAME} "echo 'Connected via Tailscale'" 2>/dev/null; then
  echo "✓ Can connect via Tailscale hostname"
else
  echo "⚠ WARNING: Cannot connect via Tailscale hostname (may need full FQDN)"
fi

echo ""
echo "[5/5] Update hosts.yml manually:"
echo "  ${HOST}:"
echo "    ansible_host: ${TAILSCALE_HOSTNAME}"
echo "    ansible_user: ansible"
echo ""
echo "Next: ./scripts/run-ansible.sh prod ${HOST} production"
