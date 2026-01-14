#!/bin/bash
# Diagnostic script for lego Docker mount issues
# Run this on rigel to identify the root cause

set -euo pipefail

echo "============================================================================"
echo "Lego Docker Mount Diagnostic"
echo "============================================================================"
echo ""

echo "1. Checking Docker version and info..."
echo "----------------------------------------"
docker --version
docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo "Docker Compose not found"
docker info | grep -E "Server Version|Storage Driver|Docker Root Dir" || true
echo ""

echo "2. Checking filesystem for /opt/lego/data..."
echo "----------------------------------------"
ls -ld /opt/lego/data
file /opt/lego/data
stat /opt/lego/data
df -h /opt/lego/data
mount | grep -E "/opt|mmcblk" || true
echo ""

echo "3. Testing simple Docker mount with alpine..."
echo "----------------------------------------"
if docker run --rm -v /opt/lego/data:/test alpine ls -la /test 2>&1; then
    echo "✓ Alpine mount test: SUCCESS"
else
    echo "✗ Alpine mount test: FAILED"
fi
echo ""

echo "4. Testing Docker mount with lego image (version check only)..."
echo "----------------------------------------"
if docker run --rm -v /opt/lego/data:/lego:ro goacme/lego:v4.14.2 --version 2>&1; then
    echo "✓ Lego mount test (read-only): SUCCESS"
else
    echo "✗ Lego mount test (read-only): FAILED"
fi
echo ""

echo "5. Testing different mount paths..."
echo "----------------------------------------"
for TEST_PATH in /var/lib/lego /tmp/lego-test /home/deploy/lego-test; do
    echo "Testing: $TEST_PATH"
    sudo mkdir -p "$TEST_PATH" 2>/dev/null || true
    sudo chmod 755 "$TEST_PATH" 2>/dev/null || true
    if docker run --rm -v "$TEST_PATH:/lego:rw" goacme/lego:v4.14.2 --version 2>&1 | head -1; then
        echo "  ✓ $TEST_PATH: SUCCESS"
    else
        echo "  ✗ $TEST_PATH: FAILED"
    fi
    sudo rm -rf "$TEST_PATH" 2>/dev/null || true
done
echo ""

echo "6. Checking Docker daemon logs (last 50 lines)..."
echo "----------------------------------------"
sudo journalctl -u docker -n 50 --no-pager | grep -iE "mount|lego|error|failed" | tail -20 || echo "No relevant errors found"
echo ""

echo "7. Checking for existing lego containers/volumes..."
echo "----------------------------------------"
docker ps -a | grep lego || echo "No lego containers found"
docker volume ls | grep lego || echo "No lego volumes found"
echo ""

echo "8. Testing Docker Compose with minimal config..."
echo "----------------------------------------"
cat > /tmp/test-compose.yml <<EOF
services:
  test:
    image: goacme/lego:v4.14.2
    volumes:
      - /opt/lego/data:/lego:rw
    command: ["--version"]
EOF

cd /tmp
if docker compose -f test-compose.yml run --rm test 2>&1 | head -3; then
    echo "✓ Docker Compose test: SUCCESS"
else
    echo "✗ Docker Compose test: FAILED"
fi
rm -f test-compose.yml
echo ""

echo "9. Checking SELinux/AppArmor status..."
echo "----------------------------------------"
if command -v getenforce &>/dev/null; then
    echo "SELinux: $(getenforce 2>/dev/null || echo 'not installed')"
fi
if command -v aa-status &>/dev/null; then
    aa-status 2>/dev/null | head -5 || echo "AppArmor status unavailable"
else
    echo "AppArmor: not installed or not accessible"
fi
echo ""

echo "10. Checking Docker storage driver and data root..."
echo "----------------------------------------"
docker info | grep -E "Storage Driver|Docker Root Dir|Backing Filesystem" || true
echo ""

echo "============================================================================"
echo "Diagnostic complete"
echo "============================================================================"
