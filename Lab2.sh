#!/usr/bin/env bash
set -euxo pipefail

##############################################
# Lab A – FINAL BREAK SCRIPT
# - Removes NIC configuration
# - Removes GRUB serial console parameters
# - Delays reboot using nohup so CSE exits cleanly
##############################################

echo "[LabA] Starting break script..." | tee /var/log/labA.log

#
# 1. BREAK THE NIC CONFIGURATION
#    (works for RHEL 8/9/10 with NetworkManager)
#
echo "[LabA] Removing all NetworkManager connection profiles..." | tee -a /var/log/labA.log
nmcli connection show || true
nmcli connection delete "$(nmcli -t -f NAME connection show | grep -v '^lo$' || true)" || true
rm -f /etc/sysconfig/network-scripts/ifcfg-* || true
sync

#
# 2. BREAK GRUB SERIAL CONSOLE OUTPUT
#
echo "[LabA] Removing all serial console parameters from GRUB..." | tee -a /var/log/labA.log

# Remove any console=ttyS0... entries
sed -i 's/console=ttyS0[^ ]*//g' /etc/default/grub

# Remove GRUB terminal settings
sed -i '/GRUB_TERMINAL_OUTPUT/d' /etc/default/grub
sed -i '/GRUB_TERMINAL/d' /etc/default/grub

# Regenerate GRUB config (RHEL10)
if [[ -x /usr/sbin/grub2-mkconfig ]]; then
    grub2-mkconfig -o /boot/grub2/grub.cfg || true
else
    # Just in case symlink or minimal bootloader
    grub-mkconfig -o /boot/grub2/grub.cfg || true
fi
sync

#
# 3. DELAYED REBOOT → using nohup so CSE doesn't hang
#
echo "[LabA] Scheduling delayed reboot (30 seconds)..." | tee -a /var/log/labA.log

nohup bash -c "
    echo '[LabA] Sleeping 30s before reboot...' >> /var/log/labA-reboot.log 2>&1
    sleep 30
    echo '[LabA] Rebooting now...' >> /var/log/labA-reboot.log 2>&1
    /usr/sbin/reboot
" >/dev/null 2>&1 &

echo "[LabA] Script completed — VM will reboot in 30 seconds." | tee -a /var/log/labA.log
exit 0