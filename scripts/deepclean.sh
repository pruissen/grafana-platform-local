#!/bin/bash
echo "⚠️  STARTING DEEP CLEAN (MicroK8s & K3s cleanup)..."

# 1. Kill K3s (if present)
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then /usr/local/bin/k3s-uninstall.sh; fi
sudo killall -9 k3s 2>/dev/null

# 2. Kill MicroK8s
sudo snap remove microk8s --purge 2>/dev/null

# 3. Clean Mounts
echo "   - Unmounting virtual storage..."
sudo umount /var/lib/rancher 2>/dev/null || true
sudo umount /var/snap/microk8s/common 2>/dev/null || true

# 4. Clean Files
rm -rf ~/.kube
rm -rf ~/.helm
sudo rm -rf /etc/rancher /var/lib/rancher
sudo rm -rf /var/snap/microk8s

# 5. Clean Terraform
cd "$(dirname "$0")/../terraform" || exit
rm -rf .terraform .terraform.lock.hcl *.tfstate *.tfstate.backup

# 6. NETWORKING RESET
echo "   - Cleaning network interfaces..."
sudo ip link delete cni0 2>/dev/null
sudo ip link delete flannel.1 2>/dev/null
sudo ip link delete kube-bridge 2>/dev/null
sudo iptables -F && sudo iptables -t nat -F

echo "✅ System Cleaned."