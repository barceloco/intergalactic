#!/bin/bash
# Helper script to encrypt home partition using passphrase from Ansible secrets
# Usage: ./encrypt-home-partition.sh <device> <base64-passphrase>

set -euo pipefail

DEVICE="${1:-}"
PASSPHRASE_B64="${2:-}"

if [ -z "$DEVICE" ] || [ -z "$PASSPHRASE_B64" ]; then
    echo "Usage: $0 <device> <base64-passphrase>"
    echo ""
    echo "Example:"
    echo "  $0 /dev/nvme0n1p3 \"dGhpcyBpcyBhIHNhbXBsZSBwYXNzcGhyYXNlIGluIGJhc2U2NA==\""
    exit 1
fi

if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device"
    exit 1
fi

echo "WARNING: This will DESTROY all data on $DEVICE!"
echo "Device: $DEVICE"
read -p "Type 'YES' to continue: " confirm

if [ "$confirm" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

# Decode passphrase - support both base64 and hex formats
# Try base64 first (most common)
if PASSPHRASE=$(echo -n "$PASSPHRASE_B64" | base64 -d 2>/dev/null); then
    if [ -n "$PASSPHRASE" ]; then
        echo "Using base64-encoded passphrase"
    else
        echo "Error: Decoded base64 passphrase is empty."
        exit 1
    fi
# Try hex format (64 hex chars = 32 bytes)
elif echo -n "$PASSPHRASE_B64" | grep -qE '^[0-9a-fA-F]{64}$'; then
    if PASSPHRASE=$(echo -n "$PASSPHRASE_B64" | xxd -r -p 2>/dev/null); then
        echo "Using hex-encoded passphrase"
    else
        echo "Error: Failed to decode hex passphrase."
        exit 1
    fi
else
    echo "Error: Passphrase must be either base64-encoded or 64-character hex string."
    echo "Base64 example: $(echo -n 'test' | base64)"
    echo "Hex example: $(echo -n 'test' | xxd -p | tr -d '\n')"
    exit 1
fi

if [ -z "$PASSPHRASE" ]; then
    echo "Error: Decoded passphrase is empty. Please check your input."
    exit 1
fi

# Encrypt partition
echo "Encrypting partition..."
echo -n "$PASSPHRASE" | sudo cryptsetup luksFormat "$DEVICE" -

# Open and format
echo "Opening encrypted partition..."
sudo cryptsetup open "$DEVICE" home-crypt

echo "Formatting filesystem..."
sudo mkfs.ext4 /dev/mapper/home-crypt

echo "Closing encrypted partition..."
sudo cryptsetup close home-crypt

echo ""
echo "Encryption complete!"
echo "Run Ansible playbook to configure /etc/crypttab and /etc/fstab"
