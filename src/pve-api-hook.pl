# pve-api-hook.pl
#
# This file is sourced/loaded to register the SmartRaidMon API endpoints
# with the PVE API router at /nodes/{node}/smartraidmon.
#
# It is invoked from the postinst script or via a custom PVE plugin loader.

use strict;
use warnings;

use PVE::API2::SmartRaidMon;
use PVE::API2::Nodes;

# Register under /nodes/{node}/smartraidmon
PVE::API2::Nodes->register_method({
    subclass => 'PVE::API2::SmartRaidMon',
    path     => 'smartraidmon',
});

1;
