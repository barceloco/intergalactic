#!/bin/bash
# Helper script to partition 128GB drives with standard layout:
# - Partition 1: 1GB (FAT32, /boot)
# - Partition 2: 32GB (ext4, /)
# - Partition 3: ~95GB (ext4, /home)
#
# Usage: ./setup-partitions.sh <device>
# Example: ./setup-partitions.sh /dev/sda

set -euo pipefail

DEVICE="${1:-}"

if [ -z "$DEVICE" ]; then
    echo "Usage: $0 <device>"
    echo ""
    echo "Example:"
    echo "  $0 /dev/sda"
    echo ""
    echo "WARNING: This will DESTROY all data on the device!"
    echo "Make sure you have backups before proceeding."
    exit 1
fi

if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device"
    exit 1
fi

# Check if device is mounted
if mountpoint -q "$DEVICE"* 2>/dev/null || grep -q "$DEVICE" /proc/mounts 2>/dev/null; then
    echo "Error: Device $DEVICE or its partitions are mounted"
    echo "Please unmount all partitions before proceeding"
    exit 1
fi

echo "============================================================================"
echo "Partition Setup for 128GB Drive"
echo "============================================================================"
echo "Device: $DEVICE"
echo ""
echo "This will create:"
echo "  - Partition 1: 1GB (FAT32, /boot)"
echo "  - Partition 2: 32GB (ext4, /)"
echo "  - Partition 3: ~95GB (ext4, /home)"
echo ""
echo "WARNING: This will DESTROY all data on $DEVICE!"
echo "============================================================================"
read -p "Type 'YES' to continue: " confirm

if [ "$confirm" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

# Create GPT partition table
echo "Creating GPT partition table..."
sudo parted "$DEVICE" --script mklabel gpt

# Create partitions
echo "Creating partitions..."
# Partition 1: 1GB (FAT32, /boot)
sudo parted "$DEVICE" --script mkpart primary fat32 1MiB 1025MiB
sudo parted "$DEVICE" --script set 1 esp on

# Partition 2: 32GB (ext4, /)
sudo parted "$DEVICE" --script mkpart primary ext4 1025MiB 33793MiB

# Partition 3: Rest of disk (ext4, /home)
sudo parted "$DEVICE" --script mkpart primary ext4 33793MiB 100%

# Format partitions
echo "Formatting partitions..."
sudo mkfs.vfat -F 32 "${DEVICE}1"
sudo mkfs.ext4 -F "${DEVICE}2"
sudo mkfs.ext4 -F "${DEVICE}3"

echo ""
echo "============================================================================"
echo "Partitioning complete!"
echo "============================================================================"
echo "Partitions created:"
sudo parted "$DEVICE" --script print
echo ""
echo "Next steps:"
echo "  1. Install OS to partitions 1 and 2 (/boot and /)"
echo "  2. Add /home mount to /etc/fstab after OS installation:"
echo "     UUID=$(sudo blkid -s UUID -o value ${DEVICE}3) /home ext4 defaults 0 2"
echo "  3. Run bootstrap: ./scripts/run-ansible.sh prod <hostname> bootstrap"
echo "============================================================================"
