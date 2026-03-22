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

    # Nodes.pm structure (PVE 8.x):
    #   Line 1:    package PVE::API2::Nodes::Nodeinfo;
    #   Lines ~114-210: __PACKAGE__->register_method({ subclass => ..., path => ... })
    #              for qemu, disks, storage, etc. — all in Nodeinfo context
    #   Line ~2689: package PVE::API2::Nodes;
    #   Last line:  });1;   (no standalone "1;")
    #
    # We insert our registration right after the Disks subclass registration,
    # in the Nodeinfo package context alongside all other sub-routes.
    perl -e '
        use strict;
        use warnings;
        my $file = shift;
        open my $fh, "<", $file or die "Cannot read $file: $!\n";
        my @lines = <$fh>;
        close $fh;

        # Find the Disks registration block to insert after it
        my $insert_after = -1;
        for my $i (0 .. $#lines) {
            if ($lines[$i] =~ /subclass\s*=>\s*"PVE::API2::Disks"/) {
                # Find the closing "});" of this block
                for my $j ($i .. $#lines) {
                    if ($lines[$j] =~ /^\}\);/) {
                        $insert_after = $j;
                        last;
                    }
                }
                last;
            }
        }
        die "Could not find PVE::API2::Disks registration in $file\n" if $insert_after < 0;

        open my $out, ">", $file or die "Cannot write $file: $!\n";
        for my $i (0 .. $#lines) {
            print $out $lines[$i];
            if ($i == $insert_after) {
                print $out "\n__PACKAGE__->register_method({\n";
                print $out "    subclass => \"PVE::API2::SmartRaidMon\",\n";
                print $out "    path => \"smartraidmon\",\n";
                print $out "});\n";
            }
        }
        close $out;
    ' "$NODES_PM"

    # Add 'use' statement after 'use PVE::API2::Disks;'
    if ! grep -q "use PVE::API2::SmartRaidMon;" "$NODES_PM"; then
        sed -i '/^use PVE::API2::Disks;/a use PVE::API2::SmartRaidMon;' "$NODES_PM"
    fi

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
