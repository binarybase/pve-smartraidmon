#!/bin/bash
#
# uninstall.sh - Remove pve-smartraidmon from a PVE host
#
set -euo pipefail

echo "=== PVE Smart RAID Monitor - Uninstall ==="

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

echo "[1/4] Removing Perl API module..."
rm -f /usr/share/perl5/PVE/API2/SmartRaidMon.pm

echo "[2/4] Removing smartctl scanner..."
rm -rf /usr/libexec/pve-smartraidmon

echo "[3/4] Removing JavaScript GUI and API hook..."
rm -f /usr/share/pve-manager/js/SmartRaidMon.js
rm -rf /usr/share/pve-smartraidmon

echo "[4/4] Removing script tag from PVE index..."
INDEX_FILE="/usr/share/pve-manager/index.html.tpl"
if [ -f "$INDEX_FILE" ]; then
    sed -i '/SmartRaidMon\.js/d' "$INDEX_FILE"
fi

echo ""
echo "Restarting pveproxy..."
systemctl restart pveproxy

echo ""
echo "=== Uninstall complete ==="
