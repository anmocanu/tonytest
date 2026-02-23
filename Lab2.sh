#!/bin/bash
###############################################################################
# Lab2.sh - LinuxLab302 Break Script (RHEL 10)
#
# Simulates a VM migrated from on-premises to Azure without proper preparation.
#
# Issues introduced:
#   1. NIC set to static IP (breaks Azure DHCP-based connectivity)
#      - Rewrites the NM keyfile (.nmconnection) with static IP
#      - Creates legacy ifcfg-eth0 for the student to find/fix
#      - Disables cloud-init network config so it won't auto-fix on reboot
#   2. Serial Console removed from GRUB (breaks Azure Serial Console)
#      - Strips all serial directives from /etc/default/grub
#      - Removes console=ttyS0 from BLS entries (/boot/loader/entries/)
#      - Regenerates grub.cfg
#
# After this script runs and the VM reboots, the student will need to:
#   - Use a Rescue VM to mount the broken OS disk
#   - Change BOOTPROTO from static to dhcp in ifcfg-eth0
#   - Re-enable cloud-init network or fix the NM profile
#   - Configure Serial Console in /etc/default/grub
#   - Add console=ttyS0 back to BLS entries
#   - Regenerate grub.cfg with grub2-mkconfig
###############################################################################

set -e

###############################################################################
# 1. Configure NIC with static IP (simulating on-premises static config)
###############################################################################

# --- 1a. Disable cloud-init network configuration so it won't override our
#         static IP on reboot (simulates on-prem: no cloud-init at all) ---
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg <<'EOF'
network: {config: disabled}
EOF

# --- 1b. Rewrite the actual NM keyfile that RHEL 10 uses ---
NM_CONN_DIR="/etc/NetworkManager/system-connections"
NM_CONN_FILE=$(ls "${NM_CONN_DIR}"/*.nmconnection 2>/dev/null | head -1)

if [ -n "$NM_CONN_FILE" ]; then
    # Backup the original
    cp "$NM_CONN_FILE" "${NM_CONN_FILE}.orig.bak"

    # Rewrite the [ipv4] section to use static IP
    sed -i '/^\[ipv4\]/,/^\[/{
        s/^method=.*/method=manual/
    }' "$NM_CONN_FILE"

    # Remove any existing address/gateway/dns lines under [ipv4] and add static ones
    sed -i '/^\[ipv4\]/,/^\[/{
        /^address/d
        /^gateway/d
        /^dns=/d
    }' "$NM_CONN_FILE"

    # Insert static IP settings right after [ipv4]
    sed -i '/^\[ipv4\]/a address1=10.10.10.10/24,10.10.10.1\ndns=168.63.129.16;' "$NM_CONN_FILE"
fi

# --- 1c. Also modify via nmcli to cover the active profile ---
CON_NAME=$(nmcli -t -f NAME con show --active 2>/dev/null | head -1)
if [ -n "$CON_NAME" ]; then
    nmcli con mod "$CON_NAME" ipv4.method manual \
        ipv4.addresses "10.10.10.10/24" \
        ipv4.gateway "10.10.10.1" \
        ipv4.dns "168.63.129.16" 2>/dev/null || true
fi

# --- 1d. Create legacy ifcfg-eth0 for the student to find and fix ---
mkdir -p /etc/sysconfig/network-scripts
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<'IFCFG'
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
NAME=eth0
DEVICE=eth0
ONBOOT=yes
IPADDR=10.10.10.10
NETMASK=255.255.255.0
GATEWAY=10.10.10.1
DNS1=168.63.129.16
IFCFG

###############################################################################
# 2. Remove Serial Console configuration from GRUB
###############################################################################

# Backup original grub defaults
cp /etc/default/grub /etc/default/grub.orig.bak

# --- 2a. Clean /etc/default/grub ---

# Remove console=ttyS0 and earlyprintk=ttyS0 parameters from GRUB_CMDLINE_LINUX
sed -i 's/console=ttyS0[^ "]*//g' /etc/default/grub
sed -i 's/earlyprintk=ttyS0[^ "]*//g' /etc/default/grub

# Clean up extra whitespace left behind
sed -i '/GRUB_CMDLINE_LINUX/s/  \+/ /g' /etc/default/grub
sed -i '/GRUB_CMDLINE_LINUX/s/" /"/g' /etc/default/grub
sed -i '/GRUB_CMDLINE_LINUX/s/ "/"/g' /etc/default/grub

# Remove ALL serial-related GRUB directives
sed -i '/^GRUB_TERMINAL_OUTPUT/d' /etc/default/grub
sed -i '/^GRUB_TERMINAL_INPUT/d' /etc/default/grub
sed -i '/^GRUB_TERMINAL=/d' /etc/default/grub
sed -i '/^GRUB_SERIAL_COMMAND/d' /etc/default/grub

# Set terminal output to console only (no serial)
echo 'GRUB_TERMINAL_OUTPUT="console"' >> /etc/default/grub

# --- 2b. Fix BLS entries (RHEL 10 uses GRUB_ENABLE_BLSCFG=true) ---
#     The kernel cmdline with console=ttyS0 lives in BLS snippet files,
#     not in grub.cfg. We must strip it from each entry.
for entry in /boot/loader/entries/*.conf; do
    if [ -f "$entry" ]; then
        # Backup
        cp "$entry" "${entry}.orig.bak"
        # Remove console=ttyS0* and earlyprintk=ttyS0* from the options line
        sed -i 's/console=ttyS0[^ ]*//g' "$entry"
        sed -i 's/earlyprintk=ttyS0[^ ]*//g' "$entry"
        # Clean up double spaces
        sed -i '/^options /s/  \+/ /g' "$entry"
    fi
done

# --- 2c. Regenerate grub configuration ---
grub2-mkconfig -o /boot/grub2/grub.cfg

###############################################################################
# 3. Schedule reboot for changes to take effect
###############################################################################

# Use nohup + sleep to allow the Custom Script Extension to report success
# before the VM reboots with the broken configuration
nohup bash -c 'sleep 60 && reboot' &>/dev/null &

exit 0