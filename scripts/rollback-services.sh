#!/bin/bash
# Rollback script to restore from backup
# Usage: rollback-services.sh [backup-file]

set -euo pipefail

if [ $# -ge 1 ]; then
    BACKUP_FILE="$1"
else
    # Use most recent backup
    BACKUP_FILE=$(ls -t /opt/backups/*.tar.gz 2>/dev/null | head -1)
fi

if [ -z "${BACKUP_FILE}" ] || [ ! -f "${BACKUP_FILE}" ]; then
    echo "Error: No backup file found"
    echo "Available backups:"
    ls -lh /opt/backups/*.tar.gz 2>/dev/null || echo "No backups found"
    exit 1
fi

echo "Rolling back to: ${BACKUP_FILE}"
read -p "Are you sure you want to rollback? (yes/no): " confirm

if [ "${confirm}" != "yes" ]; then
    echo "Rollback cancelled"
    exit 0
fi

# Restore from backup
/usr/local/bin/restore-configs.sh "${BACKUP_FILE}"

# Verify services
echo "Verifying services..."
sleep 5

if systemctl is-active --quiet coredns && systemctl is-active --quiet traefik; then
    echo "✓ Rollback completed successfully"
    exit 0
else
    echo "✗ Rollback completed but services may not be running correctly"
    echo "Please check service status:"
    echo "  systemctl status coredns"
    echo "  systemctl status traefik"
    exit 1
fi
