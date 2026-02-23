#!/bin/bash
set -euxo pipefail

echo "[LabA] Starting GRUB config removal..."

# BIOS/Gen1 path
if [ -f /boot/grub2/grub.cfg ]; then
    echo "[LabA] Removing /boot/grub2/grub.cfg"
    sudo rm -f /boot/grub2/grub.cfg
else
    echo "[LabA] /boot/grub2/grub.cfg not found (continuing)"
fi

# RHEL symlink path
if [ -f /etc/grub2.cfg ]; then
    echo "[LabA] Removing /etc/grub2.cfg"
    sudo rm -f /etc/grub2.cfg
else
    echo "[LabA] /etc/grub2.cfg not found (continuing)"
fi

# UEFI / Azure Gen2 path
if [ -f /boot/efi/EFI/redhat/grub.cfg ]; then
    echo "[LabA] Removing /boot/efi/EFI/redhat/grub.cfg"
    sudo rm -f /boot/efi/EFI/redhat/grub.cfg
else
    echo "[LabA] /boot/efi/EFI/redhat/grub.cfg not found (continuing)"
fi

sudo sync
echo "[LabA] GRUB config removed, scheduling reboot..."

# Delayed reboot so the CSE reports success
nohup bash -c "
    echo '[LabA] Sleeping 30 seconds before reboot...' >> /tmp/labA-reboot.log 2>&1
    sleep 30
    echo '[LabA] Rebooting now...' >> /tmp/labA-reboot.log 2>&1
    /usr/sbin/shutdown -r now
" >/tmp/labA-reboot.log 2>&1 &

echo "[LabA] Reboot scheduled in background. Exiting script successfully."
exit 0