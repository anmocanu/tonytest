#!/bin/bash
set -euxo pipefail

###############################################
# Lab 2 – Reproduce NIC + GRUB Serial Breakage
# RHEL 10 RAW
###############################################

echo "[+] Starting Lab 2 reproduction on RHEL 10..."

########## 1. BREAK NETWORK CONFIG ##########
echo "[+] Breaking network configuration..."

# Remove network scripts (NetworkManager controlled)
sudo rm -f /etc/NetworkManager/system-connections/*.nmconnection || true
sudo rm -rf /etc/sysconfig/network-scripts || true

# Optionally disable NetworkManager (forces NIC down after reboot)
sudo systemctl disable NetworkManager || true

sync

########## 2. BREAK GRUB SERIAL CONSOLE ##########
echo "[+] Breaking GRUB serial console..."

# Delete console= entries from kernel cmdline
sudo sed -i 's/console=[^ ]*//g' /etc/default/grub

# Overwrite GRUB minimal config
sudo bash -c 'cat > /etc/default/grub <<EOF
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="RHEL10"
GRUB_DISABLE_RECOVERY=true
EOF'

# Regenerate GRUB config on EFI systems
if [ -d /boot/efi ]; then
    sudo grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
else
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg
fi

sync

########## 3. REBOOT ##########
echo "[+] Rebooting system to apply corruption..."
sudo shutdown -r now