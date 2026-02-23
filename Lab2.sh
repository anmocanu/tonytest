#!/bin/bash
set -euxo pipefail

LOG="/tmp/lab2.log"
echo "[Lab2] Starting scenario reproduction..." | tee -a $LOG

##############################################
# 1. Detect active NetworkManager connection
##############################################
ACTIVE_CONN=$(nmcli -t -f NAME,DEVICE c show --active | head -n 1 | cut -d: -f1)

if [[ -z "$ACTIVE_CONN" ]]; then
    echo "[Lab2] ERROR: No active NM connection detected" | tee -a $LOG
    exit 1
fi

echo "[Lab2] Active connection: $ACTIVE_CONN" | tee -a $LOG

##############################################
# 2. Break NIC configuration (RHEL10 RAW)
##############################################
echo "[Lab2] Breaking NIC configuration..." | tee -a $LOG

nmcli connection modify "$ACTIVE_CONN" ipv4.method disabled
nmcli connection down "$ACTIVE_CONN" || true

echo "[Lab2] NIC disabled (ipv4.method=disabled)" | tee -a $LOG

##############################################
# 3. Break GRUB serial console
##############################################
echo "[Lab2] Breaking GRUB serial console..." | tee -a $LOG

cp -f /etc/default/grub /etc/default/grub.bak

# Remove all serial console params
sed -i 's/console=ttyS0[^ ]*//g' /etc/default/grub
sed -i '/GRUB_TERMINAL_OUTPUT/d' /etc/default/grub
sed -i '/GRUB_SERIAL_COMMAND/d' /etc/default/grub

# Rebuild GRUB config
grub2-mkconfig -o /boot/grub2/grub.cfg

echo "[Lab2] GRUB updated" | tee -a $LOG

##############################################
# 4. Delayed reboot using nohup
##############################################
echo "[Lab2] Scheduling delayed reboot..." | tee -a $LOG

nohup bash -c "
    echo '[Lab2] Sleeping 30 seconds before reboot...' >> /tmp/lab2-reboot.log 2>&1
    sleep 30
    echo '[Lab2] Rebooting now...' >> /tmp/lab2-reboot.log 2>&1
    /usr/sbin/shutdown -r now
" >/tmp/lab2-reboot.log 2>&1 &

echo "[Lab2] Reboot scheduled. Exiting script cleanly." | tee -a $LOG
exit 0