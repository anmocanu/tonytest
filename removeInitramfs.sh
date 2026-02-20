#!/bin/bash
# Lab B: initramfs removed for default kernel -> kernel panic (unable to mount root fs)

set -euxo pipefail

# Identify the default kernel GRUB will boot (RHEL commonly supports grubby).
default_kernel="$(sudo grubby --default-kernel || true)"

# Fallback: pick the newest vmlinuz in /boot if grubby isn't available for some reason.
if [[ -z "${default_kernel}" ]]; then
  default_kernel="$(ls -1 /boot/vmlinuz-* 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${default_kernel}" ]]; then
  echo "ERROR: Could not determine default kernel path (no grubby, no /boot/vmlinuz-*)."
  exit 1
fi

ver="$(basename "${default_kernel}" | sed 's/^vmlinuz-//')"
initramfs="/boot/initramfs-${ver}.img"

# Lab guide symptom: removed /boot/<initramfs-kernel version.img>. [1](https://microsoft.sharepoint.com/teams/CSSLearningTeamSite/_layouts/15/Doc.aspx?sourcedoc=%7B4577097D-F82E-444B-B33A-8E4A1476E7A8%7D&file=Linux%20Advanced-Lab%201.docx&action=default&mobileredirect=true)
sudo rm -f "${initramfs}" || true

sudo sync
sudo shutdown -r now
