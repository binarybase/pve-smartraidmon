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

echo "[1/5] Removing API route from PVE::API2::Nodes..."
NODES_PM="/usr/share/perl5/PVE/API2/Nodes.pm"
if [ -f "$NODES_PM" ]; then
    sed -i '/use PVE::API2::SmartRaidMon;/d' "$NODES_PM"
    sed -i '/require PVE::API2::SmartRaidMon;/d' "$NODES_PM"
    # Remove register_method blocks containing SmartRaidMon
    # Uses paren-depth tracking to handle nested structures properly
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
    echo "       Cleaned."
fi

echo "[2/5] Removing Perl API module..."
rm -f /usr/share/perl5/PVE/API2/SmartRaidMon.pm

echo "[3/5] Removing smartctl scanner..."
rm -rf /usr/libexec/pve-smartraidmon

echo "[4/5] Removing JavaScript GUI..."
rm -f /usr/share/pve-manager/js/SmartRaidMon.js

echo "[5/5] Removing script tag from PVE index..."
INDEX_FILE="/usr/share/pve-manager/index.html.tpl"
if [ -f "$INDEX_FILE" ]; then
    sed -i '/SmartRaidMon\.js/d' "$INDEX_FILE"
fi

echo ""
echo "Restarting pveproxy..."
systemctl restart pveproxy

echo ""
echo "=== Uninstall complete ==="
