#!/bin/bash
set -o pipefail
# Update Grub
sudo rm -f /boot/efi/EFI/redhat/grub.cfg
sudo shutdown -r
