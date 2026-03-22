#!/bin/bash
#
# install.sh - Quick install script for development/testing
#
# Run on a Proxmox VE 8.x host to install the plugin without building a .deb.
# Requires root privileges.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== PVE Smart RAID Monitor - Development Install ==="
echo ""

# Check we're running on a PVE host
if [ ! -f /usr/share/pve-manager/index.html.tpl ]; then
    echo "ERROR: This does not appear to be a Proxmox VE host."
    echo "       /usr/share/pve-manager/index.html.tpl not found."
    exit 1
fi

# Check for root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

# Check smartmontools
if ! command -v smartctl &>/dev/null; then
    echo "Installing smartmontools..."
    apt-get update -qq && apt-get install -y -qq smartmontools
fi

echo "[1/5] Installing Perl API module..."
install -d /usr/share/perl5/PVE/API2
install -m 0644 "$SCRIPT_DIR/src/PVE/API2/SmartRaidMon.pm" \
    /usr/share/perl5/PVE/API2/SmartRaidMon.pm

echo "[2/5] Installing smartctl scanner..."
install -d /usr/libexec/pve-smartraidmon
install -m 0755 "$SCRIPT_DIR/src/bin/smart-raid-scan" \
    /usr/libexec/pve-smartraidmon/smart-raid-scan

echo "[3/5] Installing JavaScript GUI..."
install -d /usr/share/pve-manager/js
install -m 0644 "$SCRIPT_DIR/src/www/SmartRaidMon.js" \
    /usr/share/pve-manager/js/SmartRaidMon.js

echo "[4/5] Installing API hook..."
install -d /usr/share/pve-smartraidmon
install -m 0644 "$SCRIPT_DIR/src/pve-api-hook.pl" \
    /usr/share/pve-smartraidmon/pve-api-hook.pl

echo "[5/5] Patching PVE index template..."
INDEX_FILE="/usr/share/pve-manager/index.html.tpl"
MARKER="SmartRaidMon.js"
if ! grep -q "$MARKER" "$INDEX_FILE"; then
    sed -i '/<\/head>/i \    <script type="text/javascript" src="/pve2/js/SmartRaidMon.js"><\/script>' "$INDEX_FILE"
    echo "       Script tag injected."
else
    echo "       Script tag already present."
fi

echo ""
echo "Restarting pveproxy..."
systemctl restart pveproxy

echo ""
echo "=== Installation complete ==="
echo ""
echo "Open the Proxmox web UI and navigate to a node."
echo "You should see 'Smart Array Monitor' in the node menu."
echo ""
echo "To uninstall, run: $SCRIPT_DIR/uninstall.sh"
