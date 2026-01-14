#!/bin/bash
# Restore configuration files from backup
# Usage: restore-configs.sh <backup-file.tar.gz>

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <backup-file.tar.gz>"
    echo "Available backups:"
    ls -lh /opt/backups/*.tar.gz 2>/dev/null || echo "No backups found"
    exit 1
fi

BACKUP_FILE="$1"
RESTORE_DIR="/tmp/restore-$$"

if [ ! -f "${BACKUP_FILE}" ]; then
    echo "Error: Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

echo "Restoring from: ${BACKUP_FILE}"

# Extract backup
mkdir -p "${RESTORE_DIR}"
tar -xzf "${BACKUP_FILE}" -C "${RESTORE_DIR}"

BACKUP_CONTENT=$(find "${RESTORE_DIR}" -mindepth 1 -maxdepth 1 -type d | head -1)

if [ -z "${BACKUP_CONTENT}" ]; then
    echo "Error: Invalid backup file format"
    rm -rf "${RESTORE_DIR}"
    exit 1
fi

echo "Backup content found: ${BACKUP_CONTENT}"

# Restore CoreDNS
if [ -d "${BACKUP_CONTENT}/coredns" ]; then
    echo "Restoring CoreDNS configuration..."
    cp -r "${BACKUP_CONTENT}/coredns"/* /opt/coredns/ 2>/dev/null || true
    systemctl restart coredns
fi

# Restore Traefik
if [ -d "${BACKUP_CONTENT}/traefik" ]; then
    echo "Restoring Traefik configuration..."
    cp "${BACKUP_CONTENT}/traefik"/* /opt/traefik/ 2>/dev/null || true
    systemctl restart traefik
fi

# Restore systemd services
if [ -d "${BACKUP_CONTENT}/systemd" ]; then
    echo "Restoring systemd services..."
    cp "${BACKUP_CONTENT}/systemd"/* /etc/systemd/system/ 2>/dev/null || true
    systemctl daemon-reload
    systemctl restart coredns traefik 2>/dev/null || true
fi

# Cleanup
rm -rf "${RESTORE_DIR}"

echo "Restore completed. Please verify services are running:"
echo "  systemctl status coredns"
echo "  systemctl status traefik"
