package PVE::API2::SmartRaidMon;

use strict;
use warnings;

use PVE::RESTHandler;
use PVE::JSONSchema qw(get_standard_option);
use PVE::Tools qw(run_command);
use PVE::RPCEnvironment;

use JSON;

use base qw(PVE::RESTHandler);

my $SCAN_SCRIPT = '/usr/libexec/pve-smartraidmon/smart-raid-scan';

# Helper: run the scan script and return parsed JSON
sub run_scan {
    my ($node, $mode, @extra_args) = @_;

    my $rpcenv = PVE::RPCEnvironment::get();
    $rpcenv->check($rpcenv->get_user(), "/nodes/$node", ['Sys.Audit']);

    my @cmd = ($SCAN_SCRIPT, $mode, @extra_args);
    my $output = '';
    run_command(\@cmd, outfunc => sub { $output .= $_[0]; });

    my $data = eval { decode_json($output) };
    die "Failed to parse scan output: $@\n" if $@;
    return $data;
}

__PACKAGE__->register_method({
    name => 'index',
    path => '',
    method => 'GET',
    description => 'Smart RAID Monitor API index.',
    permissions => { user => 'all' },
    parameters => {
        additionalProperties => 0,
        properties => {
            node => get_standard_option('pve-node'),
        },
    },
    returns => {
        type => 'array',
        items => {
            type => 'object',
            properties => {
                subdir => { type => 'string' },
            },
        },
    },
    code => sub {
        return [
            { subdir => 'controllers' },
            { subdir => 'drives' },
            { subdir => 'drive-detail' },
            { subdir => 'summary' },
        ];
    },
});

__PACKAGE__->register_method({
    name => 'summary',
    path => 'summary',
    method => 'GET',
    description => 'Get summary of all HP Smart Array controllers and drives with S.M.A.R.T. health.',
    protected => 1,
    permissions => {
        check => ['perm', '/nodes/{node}', ['Sys.Audit']],
    },
    parameters => {
        additionalProperties => 0,
        properties => {
            node => get_standard_option('pve-node'),
        },
    },
    returns => {
        type => 'object',
        properties => {
            controllers => {
                type => 'array',
                items => { type => 'object' },
                description => 'List of detected controllers.',
            },
            drives => {
                type => 'array',
                items => { type => 'object' },
                description => 'List of drives with S.M.A.R.T. data.',
            },
        },
    },
    code => sub {
        my ($param) = @_;
        return run_scan($param->{node}, 'summary');
    },
});

__PACKAGE__->register_method({
    name => 'controllers',
    path => 'controllers',
    method => 'GET',
    description => 'List detected HP Smart Array controllers.',
    protected => 1,
    permissions => {
        check => ['perm', '/nodes/{node}', ['Sys.Audit']],
    },
    parameters => {
        additionalProperties => 0,
        properties => {
            node => get_standard_option('pve-node'),
        },
    },
    returns => {
        type => 'array',
        items => {
            type => 'object',
            properties => {
                device => { type => 'string' },
                model  => { type => 'string', optional => 1 },
            },
        },
    },
    code => sub {
        my ($param) = @_;
        return run_scan($param->{node}, 'controllers');
    },
});

__PACKAGE__->register_method({
    name => 'drives',
    path => 'drives',
    method => 'GET',
    description => 'List all drives behind HP Smart Array controllers with S.M.A.R.T. overview.',
    protected => 1,
    permissions => {
        check => ['perm', '/nodes/{node}', ['Sys.Audit']],
    },
    parameters => {
        additionalProperties => 0,
        properties => {
            node => get_standard_option('pve-node'),
        },
    },
    returns => {
        type => 'array',
        items => {
            type => 'object',
            properties => {
                device       => { type => 'string' },
                cciss_port   => { type => 'integer' },
                model        => { type => 'string', optional => 1 },
                serial       => { type => 'string', optional => 1 },
                capacity     => { type => 'string', optional => 1 },
                health       => { type => 'string' },
                temperature  => { type => 'string', optional => 1 },
                power_on_hours => { type => 'string', optional => 1 },
            },
        },
    },
    code => sub {
        my ($param) = @_;
        return run_scan($param->{node}, 'drives');
    },
});

__PACKAGE__->register_method({
    name => 'drive_detail',
    path => 'drive-detail',
    method => 'GET',
    description => 'Get full S.M.A.R.T. details for a specific drive behind an HP Smart Array controller.',
    protected => 1,
    permissions => {
        check => ['perm', '/nodes/{node}', ['Sys.Audit']],
    },
    parameters => {
        additionalProperties => 0,
        properties => {
            node   => get_standard_option('pve-node'),
            device => {
                type => 'string',
                description => 'Block device name (e.g., sda).',
                pattern => '^[a-zA-Z0-9]+$',
            },
            port   => {
                type => 'integer',
                description => 'CCISS port number.',
                minimum => 0,
                maximum => 127,
            },
        },
    },
    returns => {
        type => 'object',
        properties => {
            info       => { type => 'object', optional => 1 },
            health     => { type => 'string' },
            attributes => {
                type => 'array',
                items => { type => 'object' },
                optional => 1,
            },
            self_tests => {
                type => 'array',
                items => { type => 'object' },
                optional => 1,
            },
            raw_output => { type => 'string', optional => 1 },
        },
    },
    code => sub {
        my ($param) = @_;
        my $device = $param->{device};
        my $port   = $param->{port};

        # Validate device name strictly
        die "Invalid device name\n" unless $device =~ /^[a-z]{2,4}[a-z]$/;
        die "Invalid port\n" unless $port =~ /^\d+$/ && $port >= 0 && $port <= 127;

        return run_scan($param->{node}, 'detail', $device, $port);
    },
});

# ---------------------------------------------------------------------------
# Self-registration with PVE node API
#
# In PVE 8.x, /nodes/{node}/* sub-routes are handled by
# PVE::API2::Nodes::Nodeinfo (defined inside Nodes.pm).
# We register as a subclass there so our endpoints appear at
# /nodes/{node}/smartraidmon/*
# ---------------------------------------------------------------------------
{
    my $registered = 0;
    for my $class (qw(
        PVE::API2::Nodes::Nodeinfo
        PVE::API2::Nodes::NodeInfo
    )) {
        next unless $class->can('register_method');
        eval {
            $class->register_method({
                subclass => __PACKAGE__,
                path => 'smartraidmon',
            });
        };
        if (!$@) {
            $registered = 1;
            last;
        }
    }
    warn "PVE::API2::SmartRaidMon: could not register API endpoint: $@\n"
        unless $registered;
}

1;
