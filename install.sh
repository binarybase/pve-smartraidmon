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
    # Back up original before any changes
    cp "$NODES_PM" "${NODES_PM}.smartraid-bak"

    # Step A: Remove any previous SmartRaidMon use/require lines
    sed -i '/use PVE::API2::SmartRaidMon;/d' "$NODES_PM"
    sed -i '/require PVE::API2::SmartRaidMon;/d' "$NODES_PM"

    # Step B: Remove any old register_method blocks for SmartRaidMon
    #         Uses paren-depth tracking to handle nested structures properly
    perl - "$NODES_PM" <<'CLEANUP_PERL'
        use strict; use warnings;
        my $file = shift;
        open my $fh, "<", $file or die "Cannot read $file: $!\n";
        my @lines = <$fh>; close $fh;

        my @out;
        my $i = 0;
        while ($i <= $#lines) {
            if ($lines[$i] =~ /__PACKAGE__->register_method\s*\(/) {
                my @block = ();
                my $depth = 0;
                while ($i <= $#lines) {
                    push @block, $lines[$i];
                    for my $c (split //, $lines[$i]) {
                        $depth++ if $c eq '(';
                        $depth-- if $c eq ')';
                    }
                    $i++;
                    last if $depth <= 0;
                }
                my $block_text = join('', @block);
                if ($block_text =~ /SmartRaidMon/) {
                    # Skip trailing blank lines
                    while ($i <= $#lines && $lines[$i] =~ /^\s*$/) { $i++; }
                    next;
                }
                push @out, @block;
            } else {
                push @out, $lines[$i];
                $i++;
            }
        }
        open my $ofh, ">", $file or die "Cannot write $file: $!\n";
        print $ofh @out; close $ofh;
CLEANUP_PERL

    # Step C: Insert SmartRaidMon registration after the Disks block,
    #         using paren-depth tracking to find the exact block end.
    perl - "$NODES_PM" <<'INSERT_PERL'
        use strict; use warnings;
        my $file = shift;
        open my $fh, "<", $file or die "Cannot read $file: $!\n";
        my @lines = <$fh>; close $fh;

        my $insert_after = -1;
        for my $i (0 .. $#lines) {
            if ($lines[$i] =~ /subclass\s*=>\s*["']PVE::API2::Disks["']/) {
                # Walk backwards to find the register_method opening
                my $block_start = $i;
                for (my $k = $i; $k >= 0; $k--) {
                    if ($lines[$k] =~ /__PACKAGE__->register_method\s*\(/) {
                        $block_start = $k;
                        last;
                    }
                }
                # Track paren depth from the opening to find the end
                my $depth = 0;
                for my $j ($block_start .. $#lines) {
                    for my $c (split //, $lines[$j]) {
                        $depth++ if $c eq '(';
                        $depth-- if $c eq ')';
                    }
                    if ($depth <= 0) {
                        $insert_after = $j;
                        last;
                    }
                }
                last;
            }
        }
        die "Could not find PVE::API2::Disks registration in $file\n"
            if $insert_after < 0;

        open my $ofh, ">", $file or die "Cannot write $file: $!\n";
        for my $i (0 .. $#lines) {
            print $ofh $lines[$i];
            if ($i == $insert_after) {
                print $ofh "\n";
                print $ofh "__PACKAGE__->register_method ({\n";
                print $ofh "   subclass => \"PVE::API2::SmartRaidMon\",\n";
                print $ofh "   path => 'smartraidmon',\n";
                print $ofh "});\n";
            }
        }
        close $ofh;
INSERT_PERL

    # Step D: Add 'use' statement after 'use PVE::API2::Disks;'
    if ! grep -q "use PVE::API2::SmartRaidMon;" "$NODES_PM"; then
        sed -i '/^use PVE::API2::Disks;/a use PVE::API2::SmartRaidMon;' "$NODES_PM"
    fi

    # Verify it compiles correctly
    if perl -c "$NODES_PM" 2>/dev/null; then
        echo "       API route registered and verified."
        rm -f "${NODES_PM}.smartraid-bak"
    else
        echo "ERROR: Nodes.pm failed syntax check after patching!"
        echo "       Restoring backup..."
        cp "${NODES_PM}.smartraid-bak" "$NODES_PM"
        rm -f "${NODES_PM}.smartraid-bak"
        echo "       Restored original. Please report this issue."
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
