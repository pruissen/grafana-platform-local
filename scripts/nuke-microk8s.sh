#!/bin/bash
echo "☢️  NUKING MICROK8S (Force Removal) ☢️"

# 1. Stop Services
echo "   - Stopping Snapd & MicroK8s services..."
sudo systemctl stop snapd
sudo systemctl stop microk8s 2>/dev/null

# 2. Force Unmount (The most critical part)
echo "   - Forcefully unmounting MicroK8s volumes..."
sudo umount -l /var/snap/microk8s/common 2>/dev/null
sudo umount -l /var/snap/microk8s 2>/dev/null
sudo umount -l /snap/microk8s 2>/dev/null

# Loop to find any stragglers
for mount in $(mount | grep microk8s | awk '{print $3}'); do
    echo "     Unmounting $mount..."
    sudo umount -l "$mount"
done

# 3. Destroy Files
echo "   - Deleting MicroK8s data..."
sudo rm -rf /var/snap/microk8s
sudo rm -rf /snap/microk8s
sudo rm -rf /root/snap/microk8s
sudo rm -rf /home/$USER/snap/microk8s

# 4. Clean Systemd
echo "   - Cleaning systemd units..."
sudo rm -f /etc/systemd/system/snap.microk8s*
sudo systemctl daemon-reload

# 5. Restart Snapd (Clean slate)
echo "   - Restarting Snapd..."
sudo systemctl start snapd

# 6. Cleanup Networking
echo "   - Cleaning Network Interfaces..."
sudo ip link delete cni0 2>/dev/null
sudo ip link delete flannel.1 2>/dev/null
sudo iptables -F && sudo iptables -t nat -F

echo "✅ MicroK8s Nuked. System is ready for K3s."