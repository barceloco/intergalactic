#!/bin/bash
# Diagnostic script for cert_issuer role
# Run this on rigel to check certificate issuance status

set -euo pipefail

echo "============================================================================"
echo "Certificate Issuer Diagnostic"
echo "============================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check() {
    local name="$1"
    local cmd="$2"
    
    echo -n "Checking ${name}... "
    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

echo "1. Docker Status"
echo "----------------------------------------"
check "Docker is installed" "command -v docker"
check "Docker daemon is running" "docker info &>/dev/null"
docker version --format 'Server: {{.Server.Version}}' 2>/dev/null || echo "Docker not accessible"
echo ""

echo "2. Lego Container Image"
echo "----------------------------------------"
if docker image inspect goacme/lego:v4.31.0 &>/dev/null; then
    echo -e "${GREEN}✓${NC} Lego image exists"
    docker image inspect goacme/lego:v4.31.0 --format 'Size: {{.Size}} bytes, Created: {{.Created}}' 2>/dev/null || true
else
    echo -e "${YELLOW}⚠${NC} Lego image not found locally (will be pulled)"
fi
echo ""

echo "3. Directory Structure"
echo "----------------------------------------"
for dir in "/opt/lego" "/opt/lego/data" "/etc/lego" "/opt/traefik/certs"; do
    if [[ -d "$dir" ]]; then
        echo -e "${GREEN}✓${NC} $dir exists"
        ls -ld "$dir" | awk '{print "  Permissions:", $1, "Owner:", $3":"$4}'
    else
        echo -e "${RED}✗${NC} $dir missing"
    fi
done
echo ""

echo "4. Configuration Files"
echo "----------------------------------------"
for file in "/etc/lego/lego.env" "/etc/lego/godaddy_api_key" "/etc/lego/godaddy_api_secret" "/etc/lego/deploy-targets.json"; do
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓${NC} $file exists"
        if [[ "$file" == *"godaddy_api"* ]]; then
            size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
            echo "  Size: ${size} bytes"
            if [[ $size -eq 0 ]]; then
                echo -e "  ${RED}⚠ WARNING: File is empty${NC}"
            fi
        fi
    else
        echo -e "${RED}✗${NC} $file missing"
    fi
done
echo ""

echo "5. Scripts"
echo "----------------------------------------"
for script in "/etc/lego/lego-renew.sh" "/etc/lego/lego-preflight.sh" "/etc/lego/deploy-internal-certs.sh"; do
    if [[ -f "$script" ]]; then
        if [[ -x "$script" ]]; then
            echo -e "${GREEN}✓${NC} $script (executable)"
        else
            echo -e "${YELLOW}⚠${NC} $script (not executable)"
        fi
    else
        echo -e "${RED}✗${NC} $script missing"
    fi
done
echo ""

echo "6. Existing Certificates"
echo "----------------------------------------"
if [[ -d "/opt/traefik/certs" ]]; then
    cert_count=$(find /opt/traefik/certs -name "*.crt" 2>/dev/null | wc -l)
    key_count=$(find /opt/traefik/certs -name "*.key" 2>/dev/null | wc -l)
    echo "Certificates: $cert_count"
    echo "Private keys: $key_count"
    if [[ $cert_count -gt 0 ]]; then
        echo "Certificate files:"
        find /opt/traefik/certs -name "*.crt" -exec ls -lh {} \; 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
    fi
else
    echo -e "${RED}✗${NC} Certificate directory missing"
fi
echo ""

echo "7. Lego Data Directory"
echo "----------------------------------------"
if [[ -d "/opt/lego/data" ]]; then
    if [[ -d "/opt/lego/data/certificates" ]]; then
        cert_files=$(find /opt/lego/data/certificates -name "*.crt" 2>/dev/null | wc -l)
        echo "Certificate files in lego data: $cert_files"
        if [[ $cert_files -gt 0 ]]; then
            echo "Lego certificate files:"
            find /opt/lego/data/certificates -name "*.crt" -exec ls -lh {} \; 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
        fi
    else
        echo -e "${YELLOW}⚠${NC} No certificates directory in lego data (certificates not yet issued)"
    fi
else
    echo -e "${RED}✗${NC} Lego data directory missing"
fi
echo ""

echo "8. Systemd Timer"
echo "----------------------------------------"
if systemctl list-unit-files | grep -q "lego-renew.timer"; then
    if systemctl is-active --quiet lego-renew.timer; then
        echo -e "${GREEN}✓${NC} Timer is active"
    else
        echo -e "${YELLOW}⚠${NC} Timer exists but is not active"
    fi
    systemctl status lego-renew.timer --no-pager -l | head -5 || true
else
    echo -e "${RED}✗${NC} Timer not found"
fi
echo ""

echo "9. Network Connectivity"
echo "----------------------------------------"
check "Can reach Let's Encrypt staging" "curl -s --max-time 5 https://acme-staging-v02.api.letsencrypt.org/directory >/dev/null"
check "Can reach Let's Encrypt production" "curl -s --max-time 5 https://acme-v02.api.letsencrypt.org/directory >/dev/null"
check "Can resolve DNS" "dig +short google.com >/dev/null"
echo ""

echo "10. GoDaddy API Credentials"
echo "----------------------------------------"
if [[ -f "/etc/lego/godaddy_api_key" ]] && [[ -f "/etc/lego/godaddy_api_secret" ]]; then
    key_size=$(stat -c%s /etc/lego/godaddy_api_key 2>/dev/null || stat -f%z /etc/lego/godaddy_api_key 2>/dev/null || echo "0")
    secret_size=$(stat -c%s /etc/lego/godaddy_api_secret 2>/dev/null || stat -f%z /etc/lego/godaddy_api_secret 2>/dev/null || echo "0")
    if [[ $key_size -gt 0 ]] && [[ $secret_size -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} API credentials files exist and are non-empty"
        echo "  Key file: ${key_size} bytes"
        echo "  Secret file: ${secret_size} bytes"
    else
        echo -e "${RED}✗${NC} API credentials files are empty"
    fi
else
    echo -e "${RED}✗${NC} API credentials files missing"
fi
echo ""

echo "============================================================================"
echo "Diagnostic complete"
echo "============================================================================"
