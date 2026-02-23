#!/usr/bin/env bash
set -euxo pipefail

LOG="/var/log/lab302-break.log"
exec > >(tee -a "$LOG") 2>&1

echo "[LAB302] Starting BREAK SCRIPT..."

#############################################
# 1. DISABLE CLOUD-INIT NETWORK RENDERER
#############################################
echo "[LAB302] Disabling cloud-init networking..."

mkdir -p /etc/cloud/cloud.cfg.d/
cat > /etc/cloud/cloud.cfg.d/99-disable-network.cfg <<EOF
network:
  config: disabled
EOF

chmod 644 /etc/cloud/cloud.cfg.d/99-disable-network.cfg
sync

#############################################
# 2. BREAK NETWORKMANAGER NIC CONFIGURATION
#############################################
echo "[LAB302] Breaking NetworkManager NIC config..."

NM_FILE="/etc/NetworkManager/system-connections/cloud-init-eth0.nmconnection"

if [[ -f "$NM_FILE" ]]; then
    chmod 600 "$NM_FILE"  # ensure we can edit

    # Overwrite IPv4 with BAD STATIC IP like in your screenshot
    sed -i "/^\[ipv4\]/,/^\[/ s/method=.*/method=manual/" "$NM_FILE"
    sed -i "/^\[ipv4\]/,/^\[/ s/address1=.*/address1=10.1.6.13\/24/" "$NM_FILE"
    sed -i "/^\[ipv4\]/,/^\[/ s/gateway=.*/gateway=0.0.0.0/" "$NM_FILE"

    # If address1 does not exist, append the block
    if ! grep -q "address1=" "$NM_FILE"; then
        cat >> "$NM_FILE" <<EOF2

[ipv4]
method=manual
address1=10.1.6.13/24
gateway=0.0.0.0
EOF2
    fi

    chmod 600 "$NM_FILE"
fi

echo "[LAB302] Reloading and breaking active connection..."
nmcli connection reload || true
nmcli connection down "cloud-init-eth0" || true
nmcli connection up "cloud-init-eth0" || true

echo "[LAB302] NIC should now be broken."

#############################################
# 3. BREAK SERIAL CONSOLE (GRUB)
#############################################
echo "[LAB302] Breaking GRUB Serial Console..."

GRUB_DEFAULT="/etc/default/grub"

sed -i 's/console=ttyS0[^ ]*//g' "$GRUB_DEFAULT"
sed -i 's/earlyprintk=ttyS0[^ ]*//g' "$GRUB_DEFAULT"
sed -i '/GRUB_TERMINAL_OUTPUT/d' "$GRUB_DEFAULT"
sed -i '/GRUB_SERIAL_COMMAND/d' "$GRUB_DEFAULT"

sed -i '/GRUB_TERMINAL=/d' "$GRUB_DEFAULT"
echo 'GRUB_TERMINAL="console"' >> "$GRUB_DEFAULT"

grub2-mkconfig -o /boot/grub2/grub.cfg || true
sync

systemctl disable serial-getty@ttyS0.service --now || true
systemctl mask serial-getty@ttyS0.service || true

#############################################
# 4. DELAYED REBOOT (CSE SAFE)
#############################################
echo "[LAB302] Scheduling reboot in 40 seconds..."

nohup bash -c "
    echo '[LAB302] Sleeping 40 seconds before reboot...' >> /var/log/lab302-reboot.log
    sleep 40
    echo '[LAB302] Rebooting now...' >> /var/log/lab302-reboot.log
    /usr/sbin/shutdown -r now
" >/dev/null 2>&1 &

echo "[LAB302] BREAK SCRIPT COMPLETE — reboot pending."
exit 0
``