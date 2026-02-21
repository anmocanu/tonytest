#!/bin/bash
# Lab A: GRUB config removed -> boot drops to "grub>" prompt
# This version uses a delayed background reboot so the Azure Custom Script
# Extension can complete successfully before the VM restarts.

set -euxo pipefail

echo "[LabA] Starting GRUB config removal..."

# Remove GRUB config in both common locations to reliably reproduce the issue.
# BIOS/Gen1-style path (RHEL-style):
if [ -f /boot/grub2/grub.cfg ]; then
    echo "[LabA] Removing /boot/grub2/grub.cfg"
    sudo rm -f /boot/grub2/grub.cfg
else
    echo "[LabA] /boot/grub2/grub.cfg not found (continuing)..."
fi

# Symlink sometimes present on RHEL:
if [ -f /etc/grub2.cfg ]; then
    echo "[LabA] Removing /etc/grub2.cfg"
    sudo rm -f /etc/grub2.cfg
fi

# UEFI/Gen2 path (RHEL on Azure):
if [ -f /boot/efi/EFI/redhat/grub.cfg ]; then
    echo "[LabA] Removing /boot/efi/EFI/redhat/grub.cfg"
    sudo rm -f /boot/efi/EFI/redhat/grub.cfg
else
    echo "[LabA] /boot/efi/EFI/redhat/grub.cfg not found (continuing)..."
fi

sudo sync
echo "[LabA] GRUB config removed, scheduling reboot..."

# IMPORTANT:
# Do NOT reboot inline. That kills the VM agent and Custom Script extension
# before it can report success, causing long deployments / VMExtensionProvisioningError.
# Instead, schedule a delayed reboot in the background.

nohup bash -c "
    echo '[LabA] Sleeping 30s before reboot...' >> /tmp/labA-reboot.log 2>&1
    sleep 30
    echo '[LabA] Rebooting now...' >> /tmp/labA-reboot.log 2>&1
    /usr/sbin/shutdown -r now
" >/tmp/labA-reboot.log 2>&1 &

echo "[LabA] Reboot scheduled in background. Exiting script successfully."
exit 0
