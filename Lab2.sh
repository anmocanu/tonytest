#!/bin/bash
set -euxo pipefail

###############################################
# Lab2.sh – RHEL 10 RAW reproduction script
# Breaks:
#   - NIC configuration
#   - GRUB serial console configuration
#   - (NO initramfs removal for Lab2)
###############################################

echo "[Lab2] Starting scenario reproduction..." | tee -a /tmp/lab2.log

### 1. Break NIC configuration
echo "[Lab2] Backing up and modifying NIC config..." | tee -a /tmp/lab2.log
NIC_NAME=$(nmcli -t -f DEVICE,STATE d | grep ':connected' | head -n1 | cut -d: -f1)

if [[ -z \"$NIC_NAME\" ]]; then
    echo \"[Lab2] ERROR: Could not detect active NIC\" | tee -a /tmp/lab2.log
    exit 1
fi

echo \"[Lab2] Detected NIC: $NIC_NAME\" | tee -a /tmp/lab2.log

# Break the NIC configuration
sed -i 's/^ONBOOT=.*/ONBOOT=no/' /etc/sysconfig/network-scripts/ifcfg-$NIC_NAME || true
echo \"[Lab2] NIC config updated to ONBOOT=no\" | tee -a /tmp/lab2.log


### 2. Break GRUB serial console
echo \"[Lab2] Breaking GRUB serial console...\" | tee -a /tmp/lab2.log

# Backup existing grub config
cp -f /etc/default/grub /etc/default/grub.bak

# Remove console directives
sed -i '/console=/d' /etc/default/grub || true

# Apply GRUB update (RHEL 10 uses grub2-mkconfig)
grub2-mkconfig -o /boot/grub2/grub.cfg


### 3. Delayed reboot via nohup job
echo \"[Lab2] Scheduling delayed reboot...\" | tee -a /tmp/lab2.log

nohup bash -c \"\
    echo '[Lab2] Sleeping 30s before reboot...' >> /tmp/lab2-reboot.log 2>&1;
    sleep 30;
    echo '[Lab2] Rebooting now.' >> /tmp/lab2-reboot.log 2>&1;
    shutdown -r now;
\" &


echo \"[Lab2] All tasks completed. System will reboot in ~30 seconds.\" | tee -a /tmp/lab2.log