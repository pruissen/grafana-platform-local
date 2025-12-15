#!/bin/bash
set -e

# Configuration
STORAGE_FILE="/data/k3s-storage.img"
MOUNT_POINT="/var/lib/rancher"
SIZE="100G"

echo "💿 [Virtual Disk] Setting up K3s Storage Fix (100GB)..."

# 1. Stop K3s
sudo systemctl stop k3s 2>/dev/null || true
sudo killall -9 k3s 2>/dev/null || true

# 2. Cleanup Old Mounts
if mountpoint -q "$MOUNT_POINT"; then
    echo "   - Unmounting existing $MOUNT_POINT..."
    sudo umount "$MOUNT_POINT"
fi

# 3. Create/Format Disk
if [ ! -f "$STORAGE_FILE" ]; then
    echo "   - Creating $SIZE disk image at $STORAGE_FILE..."
    sudo fallocate -l $SIZE "$STORAGE_FILE"
    echo "   - Formatting image as ext4..."
    sudo mkfs.ext4 -F "$STORAGE_FILE" > /dev/null
else
    echo "   - Disk image already exists. Skipping creation."
fi

# 4. Mount
if [ ! -d "$MOUNT_POINT" ]; then sudo mkdir -p "$MOUNT_POINT"; fi
echo "   - Mounting image to $MOUNT_POINT..."
sudo mount -o loop "$STORAGE_FILE" "$MOUNT_POINT"

# 5. Persist
if grep -q "$MOUNT_POINT" /etc/fstab; then
    sudo sed -i "\|$MOUNT_POINT|d" /etc/fstab
fi
echo "$STORAGE_FILE $MOUNT_POINT ext4 loop,defaults 0 0" | sudo tee -a /etc/fstab > /dev/null

echo "✅ Virtual Disk Ready: /var/lib/rancher is now ext4."