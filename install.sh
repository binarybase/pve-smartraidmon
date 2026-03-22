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
    # Pre-check: verify SmartRaidMon.pm compiles on its own
    MOD_CHECK=$(perl -c /usr/share/perl5/PVE/API2/SmartRaidMon.pm 2>&1)
    if [ $? -ne 0 ]; then
        echo "ERROR: SmartRaidMon.pm failed to compile:"
        echo "       $MOD_CHECK"
        exit 1
    fi

    # Pre-check: verify original Nodes.pm is healthy before we touch it
    ORIG_CHECK=$(perl -c "$NODES_PM" 2>&1)
    if [ $? -ne 0 ]; then
        echo "ERROR: Original Nodes.pm is already broken (possibly from a prior install):"
        echo "       $ORIG_CHECK"
        echo ""
        echo "       To restore Nodes.pm from the distribution package, run:"
        PKG=$(dpkg -S "$NODES_PM" 2>/dev/null | head -1 | cut -d: -f1)
        if [ -n "$PKG" ]; then
            echo "         apt-get install --reinstall $PKG"
        else
            echo "         apt-get install --reinstall pve-manager"
        fi
        echo "       Then run install.sh again."
        exit 1
    fi

    # Work on a temp copy — the original is never modified until verified
    TEMP_PM=$(mktemp /tmp/nodes_pm_XXXXXX.pm)
    trap 'rm -f "$TEMP_PM"' EXIT
    cp "$NODES_PM" "$TEMP_PM"

    # Step A: Remove any previous SmartRaidMon use/require lines
    sed -i '/use PVE::API2::SmartRaidMon;/d' "$TEMP_PM"
    sed -i '/require PVE::API2::SmartRaidMon;/d' "$TEMP_PM"

    # Step B: Remove any old register_method blocks for SmartRaidMon
    #         Uses paren-depth tracking to handle nested structures properly
    perl - "$TEMP_PM" <<'CLEANUP_PERL'
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
    perl - "$TEMP_PM" <<'INSERT_PERL'
        use strict; use warnings;
        my $file = shift;
        open my $fh, "<", $file or die "Cannot read $file: $!\n";
        my @lines = <$fh>; close $fh;

        my $insert_after = -1;
        for my $i (0 .. $#lines) {
            if ($lines[$i] =~ /subclass\s*=>\s*["']PVE::API2::Disks["']/) {
                my $block_start = $i;
                for (my $k = $i; $k >= 0; $k--) {
                    if ($lines[$k] =~ /__PACKAGE__->register_method\s*\(/) {
                        $block_start = $k;
                        last;
                    }
                }
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

        # Show what we're inserting after (for debugging)
        warn "Inserting SmartRaidMon registration after line " . ($insert_after + 1) .
             ": " . $lines[$insert_after] if -t STDERR;

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
    if ! grep -q "use PVE::API2::SmartRaidMon;" "$TEMP_PM"; then
        sed -i '/^use PVE::API2::Disks;/a use PVE::API2::SmartRaidMon;' "$TEMP_PM"
    fi

    # Verify the modified temp file compiles (original is still untouched)
    COMPILE_OUT=$(perl -c "$TEMP_PM" 2>&1)
    if [ $? -eq 0 ]; then
        cp "$TEMP_PM" "$NODES_PM"
        echo "       API route registered and verified."
    else
        echo "ERROR: Modified Nodes.pm failed syntax check!"
        echo "       The original file was NOT modified."
        echo ""
        echo "  Compile error:"
        echo "  $COMPILE_OUT"
        echo ""
        echo "  Changes that would have been applied:"
        diff "$NODES_PM" "$TEMP_PM" || true
        exit 1
    fi
    rm -f "$TEMP_PM"
    trap - EXIT
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
