#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/lab2-break.log"
exec > >(tee -a "$LOG") 2>&1

echo "[Lab2] Started at $(date -Is)"
echo "[Lab2] Running as: $(id)"

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local b="${f}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$f" "$b"
    echo "[Lab2] Backup created: $b"
  fi
}

#########################################
# 1. BREAK NETWORKING
#########################################

echo "[Lab2] Breaking networking..."

IFCFG_DIR="/etc/sysconfig/network-scripts"

if [[ -d "$IFCFG_DIR" ]] && compgen -G "$IFCFG_DIR/ifcfg-*" > /dev/null; then
  IFCFG_FILE="$(grep -l '^BOOTPROTO=' "$IFCFG_DIR"/ifcfg-* 2>/dev/null | head -n1 || true)"

  if [[ -n "${IFCFG_FILE:-}" && -f "$IFCFG_FILE" ]]; then
    echo "[Lab2] Found legacy ifcfg file: $IFCFG_FILE"
    backup_file "$IFCFG_FILE"

    sed -i \
      -e 's/^BOOTPROTO=.*/BOOTPROTO=static/' \
      -e '/^IPADDR=/d' \
      -e '/^PREFIX=/d' \
      -e '/^NETMASK=/d' \
      -e '/^GATEWAY=/d' \
      -e '/^DNS[0-9]*=/d' \
      "$IFCFG_FILE"

    if ! grep -q '^ONBOOT=' "$IFCFG_FILE"; then
      echo "ONBOOT=yes" >> "$IFCFG_FILE"
    else
      sed -i 's/^ONBOOT=.*/ONBOOT=yes/' "$IFCFG_FILE"
    fi

    echo "[Lab2] Updated ifcfg file:"
    sed -n '1,80p' "$IFCFG_FILE"
  fi
fi

if command -v nmcli >/dev/null 2>&1; then
  echo "[Lab2] Trying to break networking via nmcli..."

  ACTIVE_LINE="$(nmcli -t -f NAME,DEVICE,TYPE connection show --active | awk -F: '$3=="ethernet"{print; exit}' || true)"

  if [[ -n "${ACTIVE_LINE:-}" ]]; then
    CON_NAME="$(echo "$ACTIVE_LINE" | cut -d: -f1)"
    DEV_NAME="$(echo "$ACTIVE_LINE" | cut -d: -f2)"

    echo "[Lab2] Active nmcli connection: CON='$CON_NAME' DEV='$DEV_NAME'"

    backup_file "/etc/NetworkManager/system-connections/${CON_NAME}.nmconnection"

    nmcli connection modify "$CON_NAME" ipv4.method manual \
      ipv4.addresses "192.0.2.10/24" ipv4.gateway "192.0.2.1" ipv4.dns "192.0.2.53" || true

    nmcli connection down "$CON_NAME" || true
    nmcli connection up "$CON_NAME" || true

    echo "[Lab2] nmcli disabled IPv4 connectivity."
  fi
fi

#########################################
# 2. BREAK SERIAL CONSOLE (GRUB + GETTY)
#########################################

echo "[Lab2] Breaking Serial Console in GRUB..."

GRUB_DEFAULT="/etc/default/grub"

if [[ -f "$GRUB_DEFAULT" ]]; then
  backup_file "$GRUB_DEFAULT"
  sed -i \
    -e 's/console=ttyS0[^ ]*//g' \
    -e 's/console=ttyS1[^ ]*//g' \
    -e 's/console=hvc0[^ ]*//g' \
    -e 's/earlyprintk=ttyS0[^ ]*//g' \
    -e 's/earlycon=ttyS0[^ ]*//g' \
    "$GRUB_DEFAULT"

  sed -i \
    -e '/GRUB_TERMINAL/d' \
    -e '/GRUB_TERMINAL_OUTPUT/d' \
    -e '/GRUB_SERIAL_COMMAND/d' \
    "$GRUB_DEFAULT"

  echo 'GRUB_TERMINAL_OUTPUT="console"' >> "$GRUB_DEFAULT"

  echo "[Lab2] Updated GRUB default config:"
  sed -n '1,120p' "$GRUB_DEFAULT"
fi

echo "[Lab2] Disabling serial-getty..."

systemctl disable serial-getty@ttyS0.service --now || true
systemctl mask serial-getty@ttyS0.service || true

#########################################
# 3. REBUILD GRUB
#########################################

echo "[Lab2] Rebuilding grub config..."

if [[ -d /boot/grub2 ]]; then
  GRUB_OUT="/boot/grub2/grub.cfg"
elif [[ -f /etc/grub2.cfg ]]; then
  GRUB_OUT="/etc/grub2.cfg"
elif [[ -f /etc/grub2-efi.cfg ]]; then
  GRUB_OUT="/etc/grub2-efi.cfg"
else
  GRUB_OUT="/boot/grub2/grub.cfg"
fi

backup_file "$GRUB_OUT"
grub2-mkconfig -o "$GRUB_OUT" || true
echo "[Lab2] grub2-mkconfig completed."

#########################################
# 4. DELAYED REBOOT (important for CSE)
#########################################

echo "[Lab2] Scheduling reboot in 60 seconds..."

nohup bash -c '
  echo "[Lab2] Sleeping 60 seconds before reboot..." >> /var/log/lab2-break.log 2>&1
  sleep 60
  echo "[Lab2] Rebooting now..." >> /var/log/lab2-break.log 2>&1
  /usr/sbin/shutdown -r now
' >/dev/null 2>&1 &

echo "[Lab2] Reboot scheduled. Exiting script cleanly."
exit 0