#!/bin/bash
# Backup critical configuration files and data
# Run this script to create backups of CoreDNS, Traefik, and other configs

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/backups}"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

# Create backup directory
mkdir -p "${BACKUP_PATH}"

echo "Creating backup: ${BACKUP_PATH}"

# Backup CoreDNS configuration
if [ -d "/opt/coredns" ]; then
    echo "Backing up CoreDNS configuration..."
    mkdir -p "${BACKUP_PATH}/coredns"
    cp -r /opt/coredns/* "${BACKUP_PATH}/coredns/" 2>/dev/null || true
fi

# Backup Traefik configuration
if [ -d "/opt/traefik" ]; then
    echo "Backing up Traefik configuration..."
    mkdir -p "${BACKUP_PATH}/traefik"
    # Backup config files (not acme.json for security)
    cp /opt/traefik/traefik.yml "${BACKUP_PATH}/traefik/" 2>/dev/null || true
    cp /opt/traefik/dynamic.yml "${BACKUP_PATH}/traefik/" 2>/dev/null || true
    # Note: acme.json contains sensitive data, handle separately if needed
fi

# Backup systemd service files
echo "Backing up systemd services..."
mkdir -p "${BACKUP_PATH}/systemd"
cp /etc/systemd/system/coredns.service "${BACKUP_PATH}/systemd/" 2>/dev/null || true
cp /etc/systemd/system/traefik.service "${BACKUP_PATH}/systemd/" 2>/dev/null || true

# Create backup manifest
cat > "${BACKUP_PATH}/manifest.txt" <<EOF
Backup created: ${TIMESTAMP}
Hostname: $(hostname)
Backup contents:
- CoreDNS configuration
- Traefik configuration
- Systemd service files
EOF

# Compress backup
echo "Compressing backup..."
tar -czf "${BACKUP_PATH}.tar.gz" -C "${BACKUP_DIR}" "${TIMESTAMP}"
rm -rf "${BACKUP_PATH}"

echo "Backup completed: ${BACKUP_PATH}.tar.gz"

# Clean up old backups (keep last 7 days by default)
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
find "${BACKUP_DIR}" -name "*.tar.gz" -mtime +${RETENTION_DAYS} -delete

echo "Backup cleanup completed (retention: ${RETENTION_DAYS} days)"
