#!/bin/bash
# Lab A: GRUB config removed -> boot drops to "grub>" prompt

set -euxo pipefail

# Remove GRUB config in both common locations to reliably reproduce the issue.
# Lab guide symptom references /boot/grub2/grub.cfg removed. [1](https://microsoft.sharepoint.com/teams/CSSLearningTeamSite/_layouts/15/Doc.aspx?sourcedoc=%7B4577097D-F82E-444B-B33A-8E4A1476E7A8%7D&file=Linux%20Advanced-Lab%201.docx&action=default&mobileredirect=true)
sudo rm -f /boot/grub2/grub.cfg || true
sudo rm -f /etc/grub2.cfg || true

# UEFI/Gen2 commonly reads config from the EFI path on RHEL (lab mitigation regenerates it there). [1](https://microsoft.sharepoint.com/teams/CSSLearningTeamSite/_layouts/15/Doc.aspx?sourcedoc=%7B4577097D-F82E-444B-B33A-8E4A1476E7A8%7D&file=Linux%20Advanced-Lab%201.docx&action=default&mobileredirect=true)
sudo rm -f /boot/efi/EFI/redhat/grub.cfg || true

sudo sync

# Reboot to hit the failure during boot.
sudo shutdown -r now
