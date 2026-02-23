#!/bin/bash
set -euo pipefail

LOG="/var/log/linuxlab302_repro.log"
exec > >(tee -a "$LOG") 2>&1

echo "[$(date -Is)] LinuxLab-302 repro via CSE (delayed disruptive actions)"

NET_SCRIPTS_DIR="/etc/sysconfig/network-scripts"
GRUB_DEFAULT="/etc/default/grub"

if [[ ! -d "$NET_SCRIPTS_DIR" ]]; then
  echo "ERROR: $NET_SCRIPTS_DIR not found (this script targets RHEL/CentOS network-scripts)."
  exit 1
fi

# Find primary ifcfg file
NIC_FILE=""
if [[ -f "$NET_SCRIPTS_DIR/ifcfg-eth0" ]]; then
  NIC_FILE="$NET_SCRIPTS_DIR/ifcfg-eth0"
else
  NIC_FILE="$(grep -l '^DEVICE=' "$NET_SCRIPTS_DIR"/ifcfg-* 2>/dev/null | head -n1 || true)"
fi
[[ -n "$NIC_FILE" && -f "$NIC_FILE" ]] || { echo "ERROR: could not find NIC ifcfg file"; exit 1; }

TS="$(date +%Y%m%d%H%M%S)"
cp -a "$NIC_FILE" "${NIC_FILE}.bak.${TS}"
[[ -f "$GRUB_DEFAULT" ]] && cp -a "$GRUB_DEFAULT" "${GRUB_DEFAULT}.bak.${TS}" || true

echo "Will modify NIC file: $NIC_FILE"
echo "Will modify GRUB default: $GRUB_DEFAULT"
echo "Backups timestamp: $TS"

# --- IMPORTANT: Use delayed/background approach so CSE can report success first ---
# Guidance from How-Do-I-Create-a-LabBox-.aspx: schedule reboot (+1) or background sleep. [1](https://microsoft.sharepoint.com/teams/VMHub/SitePages/How-Do-I-Create-a-LabBox-.aspx?web=1)

(
  echo "[$(date -Is)] Background job starting after delay..."
  sleep 60

  echo "[$(date -Is)] 1) Force BOOTPROTO=static (lab 'cause' state is static vs dhcp) [2](https://microsoft.sharepoint.com/teams/CSSLearningTeamSite/_layouts/15/Doc.aspx?sourcedoc=%7BD53EA8AB-345E-442D-B89D-390D7A6ED758%7D&file=Linux%20Advanced-Lab%202.docx&action=default&mobileredirect=true)"
  if grep -qE '^BOOTPROTO=' "$NIC_FILE"; then
    sed -i 's/^BOOTPROTO=.*/BOOTPROTO=static/' "$NIC_FILE"
  else
    echo 'BOOTPROTO=static' >> "$NIC_FILE"
  fi

  # Make outage more likely: remove IP settings so it won't come up with a usable static config
  sed -i '/^IPADDR=/d; /^PREFIX=/d; /^NETMASK=/d; /^GATEWAY=/d; /^DNS1=/d; /^DNS2=/d' "$NIC_FILE"

  echo "[$(date -Is)] 2) Remove serial console config from GRUB (lab 'cause' state is serial console not configured) [2](https://microsoft.sharepoint.com/teams/CSSLearningTeamSite/_layouts/15/Doc.aspx?sourcedoc=%7BD53EA8AB-345E-442D-B89D-390D7A6ED758%7D&file=Linux%20Advanced-Lab%202.docx&action=default&mobileredirect=true)"
  if [[ -f "$GRUB_DEFAULT" ]]; then
    # Remove console=ttyS0... and earlyprintk=ttyS0... from cmdline, and drop serial directives
    sed -i -E \
      's/(^GRUB_CMDLINE_LINUX=.*)console=ttyS0,[^" ]+[[:space:]]*/\1/g;
       s/(^GRUB_CMDLINE_LINUX=.*)earlyprintk=ttyS0(,[0-9]+)?[[:space:]]*/\1/g' \
      "$GRUB_DEFAULT" || true

    sed -i '/^GRUB_TERMINAL_OUTPUT=/d' "$GRUB_DEFAULT" || true
    sed -i '/^GRUB_SERIAL_COMMAND=/d' "$GRUB_DEFAULT" || true
  else
    echo "WARN: $GRUB_DEFAULT missing; cannot edit defaults."
  fi

  echo "[$(date -Is)] 3) Regenerate grub.cfg (lab uses grub2-mkconfig -o /boot/grub2/grub.cfg) [2](https://microsoft.sharepoint.com/teams/CSSLearningTeamSite/_layouts/15/Doc.aspx?sourcedoc=%7BD53EA8AB-345E-442D-B89D-390D7A6ED758%7D&file=Linux%20Advanced-Lab%202.docx&action=default&mobileredirect=true)"
  if [[ -d /boot/grub2 ]]; then
    grub2-mkconfig -o /boot/grub2/grub.cfg || true
  fi

  sync
  echo "[$(date -Is)] Scheduling reboot in 1 minute (CSE-friendly) [1](https://microsoft.sharepoint.com/teams/VMHub/SitePages/How-Do-I-Create-a-LabBox-.aspx?web=1)"
  shutdown -r +1 "LinuxLab-302 repro: rebooting to apply NIC+GRUB changes"

) >/var/log/linuxlab302_repro_bg.log 2>&1 &

echo "[$(date -Is)] Background job spawned (PID $!). Exiting 0 so CSE can report success."
exit 0
