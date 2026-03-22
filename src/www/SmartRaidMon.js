/*
 * PVE Smart RAID Monitor - HP Smart Array S.M.A.R.T. Monitoring GUI
 *
 * Integrates into Proxmox VE 8.x web interface as a node-level panel.
 * Provides overview of HP Smart Array controllers, drive health status,
 * S.M.A.R.T. attributes, and self-test results.
 */

/* ========================================================================
 * 1. Drive Detail Window - shows full S.M.A.R.T. info for a single drive
 * ======================================================================== */

Ext.define('PVE.SmartRaidMon.DriveDetailWindow', {
    extend: 'Ext.window.Window',
    alias: 'widget.pveSmartRaidDriveDetail',

    title: 'S.M.A.R.T. Drive Details',
    width: 850,
    height: 620,
    layout: 'border',
    modal: true,
    bodyPadding: 0,

    initComponent: function () {
        var me = this;

        // Info panel (top)
        me.infoGrid = Ext.create('Ext.grid.Panel', {
            region: 'north',
            title: 'Drive Information',
            height: 180,
            split: true,
            scrollable: true,
            store: {
                fields: ['property', 'value'],
                data: [],
            },
            columns: [
                {
                    text: 'Property',
                    dataIndex: 'property',
                    width: 200,
                    renderer: function (v) {
                        return '<b>' + Ext.htmlEncode(v) + '</b>';
                    },
                },
                {
                    text: 'Value',
                    dataIndex: 'value',
                    flex: 1,
                    renderer: Ext.htmlEncode,
                },
            ],
        });

        // Attributes panel (center)
        me.attrGrid = Ext.create('Ext.grid.Panel', {
            region: 'center',
            title: 'S.M.A.R.T. Attributes',
            scrollable: true,
            store: {
                fields: [
                    'id',
                    'name',
                    'flag',
                    'value',
                    'worst',
                    'threshold',
                    'type',
                    'updated',
                    'when_failed',
                    'raw_value',
                ],
                data: [],
            },
            columns: [
                { text: 'ID', dataIndex: 'id', width: 45 },
                { text: 'Attribute Name', dataIndex: 'name', width: 200 },
                { text: 'Value', dataIndex: 'value', width: 60 },
                { text: 'Worst', dataIndex: 'worst', width: 60 },
                { text: 'Thresh', dataIndex: 'threshold', width: 60 },
                { text: 'Type', dataIndex: 'type', width: 90 },
                {
                    text: 'Failed',
                    dataIndex: 'when_failed',
                    width: 70,
                    renderer: function (v) {
                        if (v && v !== '-') {
                            return '<span style="color:red;font-weight:bold;">' + Ext.htmlEncode(v) + '</span>';
                        }
                        return Ext.htmlEncode(v || '-');
                    },
                },
                { text: 'Raw Value', dataIndex: 'raw_value', flex: 1, renderer: Ext.htmlEncode },
            ],
        });

        // Self-test log panel (south)
        me.testGrid = Ext.create('Ext.grid.Panel', {
            region: 'south',
            title: 'Self-Test Log',
            height: 160,
            split: true,
            collapsible: true,
            scrollable: true,
            store: {
                fields: [
                    'num',
                    'description',
                    'status',
                    'remaining',
                    'lifetime_h',
                    'lba_of_error',
                ],
                data: [],
            },
            columns: [
                { text: '#', dataIndex: 'num', width: 40 },
                { text: 'Test Type', dataIndex: 'description', width: 180, renderer: Ext.htmlEncode },
                {
                    text: 'Status',
                    dataIndex: 'status',
                    width: 200,
                    renderer: function (v) {
                        var s = Ext.htmlEncode(v || '');
                        if (/completed without error/i.test(v)) {
                            return '<span style="color:green;">' + s + '</span>';
                        } else if (v) {
                            return '<span style="color:red;">' + s + '</span>';
                        }
                        return s;
                    },
                },
                { text: 'Remaining', dataIndex: 'remaining', width: 80 },
                { text: 'Lifetime (h)', dataIndex: 'lifetime_h', width: 100 },
                { text: 'LBA of Error', dataIndex: 'lba_of_error', flex: 1, renderer: Ext.htmlEncode },
            ],
        });

        // Raw output tab
        me.rawPanel = Ext.create('Ext.panel.Panel', {
            title: 'Raw smartctl Output',
            scrollable: true,
            bodyPadding: 10,
            html: '<pre></pre>',
        });

        me.tabPanel = Ext.create('Ext.tab.Panel', {
            region: 'center',
            items: [
                {
                    title: 'Parsed Data',
                    layout: 'border',
                    items: [me.infoGrid, me.attrGrid, me.testGrid],
                },
                me.rawPanel,
            ],
        });

        Ext.apply(me, {
            layout: 'fit',
            items: [me.tabPanel],
        });

        me.callParent();
        me.loadData();
    },

    loadData: function () {
        var me = this;
        var node = me.pveNode;
        var device = me.device;
        var port = me.ccissPort;

        Proxmox.Utils.API2Request({
            url: '/nodes/' + encodeURIComponent(node) +
                 '/smartraidmon/drives/' + encodeURIComponent(device) +
                 '/' + encodeURIComponent(port),
            method: 'GET',
            failure: function (response) {
                Ext.Msg.alert(
                    'Error',
                    'Failed to load drive details: ' +
                        (response.htmlStatus || 'Unknown error'),
                );
            },
            success: function (response) {
                var data = response.result.data;

                // Populate info grid
                if (data.info) {
                    var infoData = [];
                    Ext.Object.each(data.info, function (k, v) {
                        infoData.push({
                            property: k.replace(/_/g, ' ').replace(/\b\w/g, function (c) {
                                return c.toUpperCase();
                            }),
                            value: v,
                        });
                    });
                    infoData.push({ property: 'Health Status', value: data.health || 'UNKNOWN' });
                    me.infoGrid.getStore().loadData(infoData);
                }

                // Populate attributes grid
                if (data.attributes && data.attributes.length > 0) {
                    me.attrGrid.getStore().loadData(data.attributes);
                }

                // Populate self-test grid
                if (data.self_tests && data.self_tests.length > 0) {
                    me.testGrid.getStore().loadData(data.self_tests);
                }

                // Raw output
                if (data.raw_output) {
                    me.rawPanel.setHtml(
                        '<pre style="white-space:pre-wrap;word-wrap:break-word;font-size:12px;">' +
                            Ext.htmlEncode(data.raw_output) +
                            '</pre>',
                    );
                }
            },
        });
    },
});

/* ========================================================================
 * 2. Main Node Panel - drive overview grid
 * ======================================================================== */

Ext.define('PVE.SmartRaidMon.Panel', {
    extend: 'Ext.panel.Panel',
    alias: 'widget.pveSmartRaidMonPanel',

    title: 'Smart Array Monitor',
    iconCls: 'fa fa-hdd-o',
    layout: 'border',
    bodyPadding: 0,

    initComponent: function () {
        var me = this;
        var nodename = me.pveSelNode.data.node;

        // Controller info panel
        me.controllerGrid = Ext.create('Ext.grid.Panel', {
            region: 'north',
            title: 'HP Smart Array Controllers',
            height: 130,
            split: true,
            collapsible: true,
            scrollable: true,
            store: {
                fields: ['device', 'model', 'driver'],
                data: [],
            },
            columns: [
                {
                    text: 'Device',
                    dataIndex: 'device',
                    width: 100,
                    renderer: function (v) {
                        return '<b>/dev/' + Ext.htmlEncode(v) + '</b>';
                    },
                },
                { text: 'Model', dataIndex: 'model', flex: 1, renderer: Ext.htmlEncode },
                { text: 'Driver', dataIndex: 'driver', width: 100, renderer: Ext.htmlEncode },
            ],
            emptyText: 'No HP Smart Array controllers detected.',
        });

        // Drives grid
        me.driveGrid = Ext.create('Ext.grid.Panel', {
            region: 'center',
            title: 'Drives (S.M.A.R.T. Overview)',
            scrollable: true,
            store: {
                fields: [
                    'device',
                    'cciss_port',
                    'model',
                    'serial',
                    'capacity',
                    'firmware',
                    'health',
                    'temperature',
                    'power_on_hours',
                    'reallocated_sectors',
                    'rotation_rate',
                ],
                data: [],
            },
            columns: [
                {
                    text: 'Device',
                    dataIndex: 'device',
                    width: 80,
                    renderer: function (v) {
                        return '<b>/dev/' + Ext.htmlEncode(v) + '</b>';
                    },
                },
                {
                    text: 'Port',
                    dataIndex: 'cciss_port',
                    width: 50,
                    renderer: function (v) {
                        return 'cciss,' + Ext.htmlEncode(String(v));
                    },
                },
                { text: 'Model', dataIndex: 'model', width: 180, renderer: Ext.htmlEncode },
                { text: 'Serial', dataIndex: 'serial', width: 150, renderer: Ext.htmlEncode },
                { text: 'Capacity', dataIndex: 'capacity', width: 180, renderer: Ext.htmlEncode },
                { text: 'RPM', dataIndex: 'rotation_rate', width: 80, renderer: Ext.htmlEncode },
                {
                    text: 'Health',
                    dataIndex: 'health',
                    width: 110,
                    renderer: function (v) {
                        var s = Ext.htmlEncode(v || 'UNKNOWN');
                        if (/PASSED|OK/i.test(v)) {
                            return '<span style="color:green;font-weight:bold;">' + s + '</span>';
                        } else if (/FAIL/i.test(v)) {
                            return '<span style="color:red;font-weight:bold;">' + s + '</span>';
                        }
                        return '<span style="color:orange;">' + s + '</span>';
                    },
                },
                { text: 'Temp', dataIndex: 'temperature', width: 70, renderer: Ext.htmlEncode },
                {
                    text: 'Power-On (h)',
                    dataIndex: 'power_on_hours',
                    width: 100,
                    renderer: function (v) {
                        if (v) {
                            var n = parseInt(v, 10);
                            if (!isNaN(n)) {
                                return Ext.htmlEncode(n.toLocaleString());
                            }
                        }
                        return Ext.htmlEncode(v || '-');
                    },
                },
                {
                    text: 'Realloc',
                    dataIndex: 'reallocated_sectors',
                    width: 70,
                    renderer: function (v) {
                        var s = Ext.htmlEncode(v || '-');
                        if (v && parseInt(v, 10) > 0) {
                            return '<span style="color:orange;font-weight:bold;">' + s + '</span>';
                        }
                        return s;
                    },
                },
            ],
            emptyText: 'No drives detected behind HP Smart Array controllers.',
            listeners: {
                itemdblclick: function (view, record) {
                    Ext.create('PVE.SmartRaidMon.DriveDetailWindow', {
                        pveNode: nodename,
                        device: record.get('device'),
                        ccissPort: record.get('cciss_port'),
                        title:
                            'S.M.A.R.T. Details — /dev/' +
                            record.get('device') +
                            ' cciss,' +
                            record.get('cciss_port'),
                        autoShow: true,
                    });
                },
            },
        });

        // Status bar
        me.statusBar = Ext.create('Ext.toolbar.Toolbar', {
            region: 'south',
            items: [
                {
                    xtype: 'tbtext',
                    itemId: 'statusText',
                    text: 'Loading...',
                },
                '->',
                {
                    text: 'Refresh',
                    iconCls: 'fa fa-refresh',
                    handler: function () {
                        me.loadSummary();
                    },
                },
            ],
        });

        Ext.apply(me, {
            items: [me.controllerGrid, me.driveGrid, me.statusBar],
        });

        me.callParent();
        me.loadSummary();
    },

    loadSummary: function () {
        var me = this;
        var nodename = me.pveSelNode.data.node;
        var statusText = me.statusBar.getComponent('statusText');

        statusText.setText('Scanning controllers and drives...');

        Proxmox.Utils.API2Request({
            url: '/nodes/' + encodeURIComponent(nodename) + '/smartraidmon/summary',
            method: 'GET',
            failure: function (response) {
                statusText.setText(
                    'Error: ' + (response.htmlStatus || 'Failed to load data'),
                );
            },
            success: function (response) {
                var data = response.result.data;

                // Load controllers
                if (data.controllers) {
                    me.controllerGrid.getStore().loadData(data.controllers);
                }

                // Load drives
                if (data.drives) {
                    me.driveGrid.getStore().loadData(data.drives);

                    var total = data.drives.length;
                    var healthy = 0;
                    var failed = 0;
                    var unknown = 0;

                    Ext.Array.each(data.drives, function (d) {
                        if (/PASSED|OK/i.test(d.health)) {
                            healthy++;
                        } else if (/FAIL/i.test(d.health)) {
                            failed++;
                        } else {
                            unknown++;
                        }
                    });

                    var statusMsg =
                        total + ' drive(s) found — ' +
                        healthy + ' healthy';
                    if (failed > 0) {
                        statusMsg += ', <span style="color:red;font-weight:bold;">' +
                            failed + ' FAILED</span>';
                    }
                    if (unknown > 0) {
                        statusMsg += ', ' + unknown + ' unknown';
                    }
                    statusText.setText(statusMsg);
                } else {
                    statusText.setText('No drives found.');
                }
            },
        });
    },
});

/* ========================================================================
 * 3. Register under Disks section in PVE 8.x node navigation tree
 *
 * PVE.node.Config uses PVE.panel.Config which builds a tree navigation.
 * The "Disks" parent node has itemId 'storage'. Sub-items nested under
 * it use groups: ['storage']. We override PVE.node.Config, call
 * callParent() first (so the tree is built), then insertNodes() to
 * append our panel under "Disks".
 * ======================================================================== */

Ext.define('PVE.node.Config.SmartRaidMon', {
    override: 'PVE.node.Config',

    initComponent: function () {
        var me = this;

        // Let PVE build the full node config tree first
        me.callParent();

        var nodename = me.pveSelNode.data.node;

        // Insert our panel under the "Disks" section (itemId: 'storage')
        me.insertNodes([{
            xtype: 'pveSmartRaidMonPanel',
            title: 'Smart Array',
            iconCls: 'fa fa-hdd-o',
            itemId: 'smartraidmon',
            groups: ['storage'],
            nodename: nodename,
            pveSelNode: me.pveSelNode,
        }]);
    },
});
