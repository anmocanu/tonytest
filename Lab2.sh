#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/lab2-break.log"
exec > >(tee -a "$LOG") 2>&1

echo "[Lab2] Started at $(date -Is)"
echo "[Lab2] Running as: $(id)"

# --- helpers ---
backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local b="${f}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$f" "$b"
    echo "[Lab2] Backup: $f -> $b"
  fi
}

# --- 1) BREAK NETWORKING ---
# Try legacy ifcfg path first (your lab doc uses /etc/sysconfig/network-scripts/ifcfg-eth0) [1](https://microsoft.sharepoint.com/teams/CSSLearningTeamSite/_layouts/15/Doc.aspx?sourcedoc=%7BD53EA8AB-345E-442D-B89D-390D7A6ED758%7D&file=Linux%20Advanced-Lab%202.docx&action=default&mobileredirect=true)
IFCFG_DIR="/etc/sysconfig/network-scripts"
if [[ -d "$IFCFG_DIR" ]] && compgen -G "$IFCFG_DIR/ifcfg-*" > /dev/null; then
  echo "[Lab2] Found ifcfg files in $IFCFG_DIR"
  # pick first ethernet-like config file that contains BOOTPROTO
  IFCFG_FILE="$(grep -l '^BOOTPROTO=' "$IFCFG_DIR"/ifcfg-* 2>/dev/null | head -n1 || true)"
  if [[ -n "${IFCFG_FILE:-}" && -f "$IFCFG_FILE" ]]; then
    backup_file "$IFCFG_FILE"
    echo "[Lab2] Editing $IFCFG_FILE to simulate broken/static config..."
    # Force BOOTPROTO=static and remove IPv4 assignment fields so VM may come up without IPv4
    sed -i \
      -e 's/^BOOTPROTO=.*/BOOTPROTO=static/' \
      -e '/^IPADDR=/d' \
      -e '/^PREFIX=/d' \
      -e '/^NETMASK=/d' \
      -e '/^GATEWAY=/d' \
      -e '/^DNS[0-9]*=/d' \
      "$IFCFG_FILE"
    # Ensure it tries to come up
    grep -q '^ONBOOT=' "$IFCFG_FILE" && sed -i 's/^ONBOOT=.*/ONBOOT=yes/' "$IFCFG_FILE" || echo "ONBOOT=yes" >> "$IFCFG_FILE"
    echo "[Lab2] ifcfg updated:"
    tail -n +1 "$IFCFG_FILE" | sed -n '1,80p'
  else
    echo "[Lab2] No BOOTPROTO-based ifcfg file found; will try NetworkManager nmcli instead."
  fi
else
  echo "[Lab2] No $IFCFG_DIR/ifcfg-* found; will try NetworkManager nmcli."
fi

# NetworkManager path (common on RHEL 8/9/10)
if command -v nmcli >/dev/null 2>&1; then
  echo "[Lab2] Using nmcli to break active connection (if any)..."
  # Find an active ethernet device + connection
  ACTIVE_LINE="$(nmcli -t -f NAME,DEVICE,TYPE connection show --active | awk -F: '$3=="ethernet"{print; exit}' || true)"
  if [[ -n "${ACTIVE_LINE:-}" ]]; then
    CON_NAME="$(echo "$ACTIVE_LINE" | cut -d: -f1)"
    DEV_NAME="$(echo "$ACTIVE_LINE" | cut -d: -f2)"
    echo "[Lab2] Active ethernet connection: CON='$CON_NAME' DEV='$DEV_NAME'"

    # Make IPv4 "manual" with TEST-NET IP/GW (non-routable in your VNET) to intentionally kill connectivity
    backup_file "/etc/NetworkManager/system-connections/${CON_NAME}.nmconnection"
    nmcli connection modify "$CON_NAME" ipv4.method manual ipv4.addresses "192.0.2.10/24" ipv4.gateway "192.0.2.1" ipv4.dns "192.0.2.53" || true
    nmcli connection down "$CON_NAME" || true
    nmcli connection up "$CON_NAME" || true

    echo "[Lab2] nmcli applied a non-routable IPv4 config to simulate 'no usable IPv4'."
  else
    echo "[Lab2] No active ethernet connection found via nmcli (maybe already down)."
  fi
else
  echo "[Lab2] nmcli not present."
fi

# --- 2) BREAK SERIAL CONSOLE VIA GRUB CONFIG ---
echo "[Lab2] Step 2: Breaking Serial Console GRUB config..."

GRUB_DEFAULT="/etc/default/grub"
if [[ -f "$GRUB_DEFAULT" ]]; then
  backup_file "$GRUB_DEFAULT"
  echo "[Lab2] Editing $GRUB_DEFAULT to remove ttyS0 console params..."

  # Remove console=ttyS0 / earlyprintk=ttyS0 (the Learn article shows these params are used for serial console on RHEL) [2](https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/linux/serial-console-grub-single-user-mode)
  sed -i \
    -e 's/console=ttyS0[^ ]*//g' \
    -e 's/earlyprintk=ttyS0[^ ]*//g' \
    -e 's/  */ /g' \
    "$GRUB_DEFAULT"

  # Disable GRUB serial terminal directives (your lab shows GRUB_TERMINAL_OUTPUT + GRUB_SERIAL_COMMAND for serial console) [1](https://microsoft.sharepoint.com/teams/CSSLearningTeamSite/_layouts/15/Doc.aspx?sourcedoc=%7BD53EA8AB-345E-442D-B89D-390D7A6ED758%7D&file=Linux%20Advanced-Lab%202.docx&action=default&mobileredirect=true)
  sed -i \
    -e '/^GRUB_TERMINAL_OUTPUT=/d' \
    -e '/^GRUB_TERMINAL=/d' \
    -e '/^GRUB_SERIAL_COMMAND=/d' \
    "$GRUB_DEFAULT"

  # Force GRUB to console menu only
  echo 'GRUB_TERMINAL_OUTPUT="console"' >> "$GRUB_DEFAULT"

  echo "[Lab2] Updated $GRUB_DEFAULT (first 120 lines):"
  sed -n '1,120p' "$GRUB_DEFAULT"
else
  echo "[Lab2] WARNING: $GRUB_DEFAULT not found; cannot modify GRUB defaults."
fi

# Rebuild grub.cfg (lab uses grub2-mkconfig -o /boot/grub2/grub.cfg) [1](https://microsoft.sharepoint.com/teams/CSSLearningTeamSite/_layouts/15/Doc.aspx?sourcedoc=%7BD53EA8AB-345E-442D-B89D-390D7A6ED758%7D&file=Linux%20Advanced-Lab%202.docx&action=default&mobileredirect=true)
echo "[Lab2] Rebuilding grub config..."
GRUB_OUT=""
if [[ -d /boot/grub2 ]]; then
  GRUB_OUT="/boot/grub2/grub.cfg"
elif [[ -f /etc/grub2.cfg ]]; then
  GRUB_OUT="/etc/grub2.cfg"
elif [[ -f /etc/grub2-efi.cfg ]]; then
  GRUB_OUT="/etc/grub2-efi.cfg"
else
  GRUB_OUT="/boot/grub2/grub.cfg"
fi

mkdir -p "$(dirname "$GRUB_OUT")" || true
backup_file "$GRUB_OUT"
grub2-mkconfig -o "$GRUB_OUT" || true
echo "[Lab2] grub2-mkconfig output path: $GRUB_OUT"

# --- 3) DELAYED REBOOT (so CSE returns success) ---
echo "[Lab2] Scheduling reboot in 60 seconds (so CSE can report back)..."
nohup bash -c 'sleep 60; echo "[Lab2] Rebooting now at $(date -Is)" >> /var/log/lab2-break.log; /sbin/shutdown -r now' >/dev/null 2>&1 &

echo "[Lab2] Completed. Log: $LOG"
exit 0