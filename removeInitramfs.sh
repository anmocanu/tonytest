#!/bin/bash
# Lab B: initramfs removed for default kernel -> kernel panic / unable to mount root fs
# This version uses a delayed background reboot so the Azure Custom Script
# Extension can complete successfully before the VM restarts.

set -euxo pipefail

echo "[LabB] Starting initramfs removal..."

# Determine the default kernel that GRUB will boot.
# On RHEL, grubby is the standard tool. Fall back to the newest vmlinuz-* if needed.
default_kernel=""

if command -v grubby >/dev/null 2>&1; then
    default_kernel="$(sudo grubby --default-kernel || true)"
fi

if [ -z "${default_kernel}" ]; then
    echo "[LabB] grubby not available or no default kernel set. Falling back to newest /boot/vmlinuz-* ..."
    default_kernel="$(ls -1 /boot/vmlinuz-* 2>/dev/null | sort | tail -n 1 || true)"
fi

if [ -z "${default_kernel}" ]; then
    echo "[LabB] ERROR: Could not determine default kernel path (no grubby and no /boot/vmlinuz-*)."
    exit 1
fi

echo "[LabB] Default kernel: ${default_kernel}"

kernel_version="$(basename "${default_kernel}" | sed 's/^vmlinuz-//')"
initramfs_path="/boot/initramfs-${kernel_version}.img"

echo "[LabB] Target initramfs: ${initramfs_path}"

if [ -f "${initramfs_path}" ]; then
    echo "[LabB] Removing ${initramfs_path}"
    sudo rm -f "${initramfs_path}"
else
    echo "[LabB] WARNING: ${initramfs_path} not found. Nothing to remove, but continuing to schedule reboot."
fi

sudo sync
echo "[LabB] Initramfs removal complete (or not found). Scheduling reboot..."

# Again, schedule reboot in the background so the extension can complete cleanly.
nohup bash -c "
    echo '[LabB] Sleeping 30s before reboot...' >> /tmp/labB-reboot.log 2>&1
    sleep 30
    echo '[LabB] Rebooting now...' >> /tmp/labB-reboot.log 2>&1
    /usr/sbin/shutdown -r now
" >/tmp/labB-reboot.log 2>&1 &

echo "[LabB] Reboot scheduled in background. Exiting script successfully."
exit 0
