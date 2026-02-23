#!/bin/bash
###############################################################################
# Lab2.sh - LinuxLab302 Break Script
# 
# Simulates a VM migrated from on-premises to Azure without proper preparation.
# 
# Issues introduced:
#   1. NIC set to static IP (breaks Azure DHCP-based connectivity)
#   2. Serial Console not configured in GRUB (breaks Azure Serial Console)
#
# After this script runs and the VM reboots, the student will need to:
#   - Use a Rescue VM to mount the broken OS disk
#   - Change BOOTPROTO from static to dhcp in ifcfg-eth0
#   - Configure Serial Console in /etc/default/grub
#   - Regenerate grub.cfg with grub2-mkconfig
###############################################################################

set -e

###############################################################################
# 1. Configure NIC with static IP (simulating on-premises static config)
###############################################################################

# Ensure the network-scripts directory exists (RHEL 10 may not have it by default)
mkdir -p /etc/sysconfig/network-scripts

# Get the active connection name
CON_NAME=$(nmcli -t -f NAME con show --active | head -1)

# Create ifcfg-eth0 with static IP configuration (wrong IP for Azure)
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

# Modify the active NetworkManager connection profile to use static IP
# This changes the stored profile; takes effect on next activation/reboot
if [ -n "$CON_NAME" ]; then
    nmcli con mod "$CON_NAME" ipv4.method manual \
        ipv4.addresses "10.10.10.10/24" \
        ipv4.gateway "10.10.10.1" \
        ipv4.dns "168.63.129.16"
fi

###############################################################################
# 2. Remove Serial Console configuration from GRUB
###############################################################################

# Backup original grub defaults
cp /etc/default/grub /etc/default/grub.orig.bak

# Remove serial console related parameters from GRUB_CMDLINE_LINUX
# Removes: console=ttyS0,115200n8  earlyprintk=ttyS0,115200  earlyprintk=ttyS0
sed -i 's/console=ttyS0[^ "]*//g' /etc/default/grub
sed -i 's/earlyprintk=ttyS0[^ "]*//g' /etc/default/grub

# Clean up extra whitespace left behind in GRUB_CMDLINE_LINUX lines
sed -i '/GRUB_CMDLINE_LINUX/s/  \+/ /g' /etc/default/grub
sed -i '/GRUB_CMDLINE_LINUX/s/" /"/g' /etc/default/grub
sed -i '/GRUB_CMDLINE_LINUX/s/ "/"/g' /etc/default/grub

# Remove serial-related GRUB directives
sed -i '/^GRUB_TERMINAL_OUTPUT/d' /etc/default/grub
sed -i '/^GRUB_SERIAL_COMMAND/d' /etc/default/grub

# Set terminal output to console only (no serial)
echo 'GRUB_TERMINAL_OUTPUT="console"' >> /etc/default/grub

# Regenerate grub configuration
grub2-mkconfig -o /boot/grub2/grub.cfg

###############################################################################
# 3. Schedule reboot for changes to take effect
###############################################################################

# Use nohup + sleep to allow the Custom Script Extension to report success
# before the VM reboots with the broken configuration
nohup bash -c 'sleep 60 && reboot' &>/dev/null &

exit 0