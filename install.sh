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
if [ -f "$NODES_PM" ]; then
    # Always clean any previous registration first (idempotent)
    sed -i '/use PVE::API2::SmartRaidMon;/d' "$NODES_PM"
    sed -i '/require PVE::API2::SmartRaidMon;/d' "$NODES_PM"
    # Remove any old register_method blocks for SmartRaidMon
    perl -0777 -i -pe 's/\n*__PACKAGE__->register_method\s*\(\{[^}]*SmartRaidMon[^}]*\}\);\n*//gs' "$NODES_PM"

    # Nodes.pm has TWO packages (Nodeinfo and Nodes) and TWO '1;' lines.
    # The LAST '1;' is in the PVE::API2::Nodes::Nodeinfo package context,
    # which is where sub-route registrations (disks, qemu, etc.) live.
    # We insert 'use' + register_method before that last '1;'.
    perl -e '
        use strict;
        use warnings;
        my $file = shift;
        open my $fh, "<", $file or die "Cannot read $file: $!\n";
        my @lines = <$fh>;
        close $fh;

        # Find the LAST "1;" line
        my $last_idx = -1;
        for my $i (0 .. $#lines) {
            $last_idx = $i if $lines[$i] =~ /^1;\s*$/;
        }
        die "Could not find terminating 1; in $file\n" if $last_idx < 0;

        open my $out, ">", $file or die "Cannot write $file: $!\n";
        for my $i (0 .. $#lines) {
            if ($i == $last_idx) {
                print $out "use PVE::API2::SmartRaidMon;\n";
                print $out "__PACKAGE__->register_method({\n";
                print $out "    subclass => \"PVE::API2::SmartRaidMon\",\n";
                print $out "    path => \"smartraidmon\",\n";
                print $out "});\n\n";
            }
            print $out $lines[$i];
        }
        close $out;
    ' "$NODES_PM"

    # Verify it compiled correctly
    if perl -c "$NODES_PM" 2>/dev/null; then
        echo "       API route registered and verified."
    else
        echo "ERROR: Nodes.pm failed syntax check after patching!"
        echo "       Attempting to roll back..."
        sed -i '/use PVE::API2::SmartRaidMon;/d' "$NODES_PM"
        sed -i '/require PVE::API2::SmartRaidMon;/d' "$NODES_PM"
        perl -0777 -i -pe 's/\n*__PACKAGE__->register_method\s*\(\{[^}]*SmartRaidMon[^}]*\}\);\n*//gs' "$NODES_PM"
        echo "       Rolled back. Please check Nodes.pm manually."
        exit 1
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
