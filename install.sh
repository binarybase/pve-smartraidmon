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

echo "[1/6] Installing Perl API module..."
install -d /usr/share/perl5/PVE/API2
install -m 0644 "$SCRIPT_DIR/src/PVE/API2/SmartRaidMon.pm" \
    /usr/share/perl5/PVE/API2/SmartRaidMon.pm

echo "[2/6] Installing smartctl scanner..."
install -d /usr/libexec/pve-smartraidmon
install -m 0755 "$SCRIPT_DIR/src/bin/smart-raid-scan" \
    /usr/libexec/pve-smartraidmon/smart-raid-scan

echo "[3/6] Installing JavaScript GUI..."
install -d /usr/share/pve-manager/js
install -m 0644 "$SCRIPT_DIR/src/www/SmartRaidMon.js" \
    /usr/share/pve-manager/js/SmartRaidMon.js

echo "[4/6] Registering API endpoint in PVE::API2::Nodes..."
NODES_PM="/usr/share/perl5/PVE/API2/Nodes.pm"
SRAID_MARKER="PVE::API2::SmartRaidMon"
if [ -f "$NODES_PM" ]; then
    if ! grep -q "$SRAID_MARKER" "$NODES_PM"; then
        # Add 'use' statement after the last existing 'use PVE::API2::' line
        LAST_USE_LINE=$(grep -n '^use PVE::API2::' "$NODES_PM" | tail -1 | cut -d: -f1)
        if [ -n "$LAST_USE_LINE" ]; then
            sed -i "${LAST_USE_LINE}a use PVE::API2::SmartRaidMon;" "$NODES_PM"
        else
            # Fallback: add after 'use strict;'
            sed -i '/^use strict;/a use PVE::API2::SmartRaidMon;' "$NODES_PM"
        fi

        # Add register_method call before the final '1;'
        sed -i '/^1;$/i \
__PACKAGE__->register_method ({\
    subclass => "PVE::API2::SmartRaidMon",\
    path => "smartraidmon",\
});' "$NODES_PM"
        echo "       API route registered."
    else
        echo "       API route already registered."
    fi
else
    echo "WARNING: $NODES_PM not found — API will not work."
fi

echo "[5/6] Patching PVE index template..."
INDEX_FILE="/usr/share/pve-manager/index.html.tpl"
MARKER="SmartRaidMon.js"
if ! grep -q "$MARKER" "$INDEX_FILE"; then
    sed -i '/<\/head>/i \    <script type="text/javascript" src="/pve2/js/SmartRaidMon.js"><\/script>' "$INDEX_FILE"
    echo "       Script tag injected."
else
    echo "       Script tag already present."
fi

echo "[6/6] Restarting pveproxy..."
systemctl restart pveproxy

echo ""
echo "=== Installation complete ==="
echo ""
echo "Open the Proxmox web UI and navigate to a node."
echo "You should see 'Smart Array' under Disks in the node tree."
echo ""
echo "To uninstall, run: $SCRIPT_DIR/uninstall.sh"
