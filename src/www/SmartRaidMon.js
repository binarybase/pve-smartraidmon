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
                 '/smartraidmon/drive-detail',
            method: 'GET',
            params: {
                device: device,
                port: port,
            },
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
    layout: { type: 'vbox', align: 'stretch' },
    bodyPadding: 0,

    initComponent: function () {
        var me = this;
        var nodename = me.pveSelNode.data.node;

        // Controller info panel
        me.controllerGrid = Ext.create('Ext.grid.Panel', {
            title: 'HP Smart Array Controllers',
            height: 100,
            collapsible: true,
            scrollable: true,
            store: {
                fields: ['device', 'model', 'driver', 'controller_model', 'controller_slot'],
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
                {
                    text: 'Controller',
                    dataIndex: 'controller_model',
                    flex: 1,
                    renderer: function (v, meta, rec) {
                        var model = v || rec.get('model') || '';
                        var slot = rec.get('controller_slot');
                        var display = Ext.htmlEncode(model);
                        if (slot !== undefined && slot !== null) {
                            display += ' (Slot ' + Ext.htmlEncode(String(slot)) + ')';
                        }
                        return display;
                    },
                },
                { text: 'Driver', dataIndex: 'driver', width: 100, renderer: Ext.htmlEncode },
            ],
            emptyText: 'No HP Smart Array controllers detected.',
        });

        // Logical drives panel
        me.logicalDriveGrid = Ext.create('Ext.grid.Panel', {
            title: 'Logical Drives',
            height: 120,
            collapsible: true,
            scrollable: true,
            hidden: true,
            store: {
                fields: ['ld_id', 'array', 'raid_level', 'size', 'status',
                    'disk_name', 'controller_model', 'controller_slot',
                    'media_errors', 'mount_points', 'caching', 'rebuild_progress'],
                data: [],
            },
            columns: [
                { text: 'Array', dataIndex: 'array', width: 55, renderer: Ext.htmlEncode },
                { text: 'LD', dataIndex: 'ld_id', width: 40 },
                {
                    text: 'RAID',
                    dataIndex: 'raid_level',
                    width: 60,
                    renderer: function (v) {
                        return v !== undefined && v !== null ? 'RAID ' + Ext.htmlEncode(String(v)) : '-';
                    },
                },
                { text: 'Size', dataIndex: 'size', width: 90, renderer: Ext.htmlEncode },
                {
                    text: 'Status',
                    dataIndex: 'status',
                    width: 220,
                    renderer: function (v) {
                        if (!v) return '-';
                        var s = Ext.htmlEncode(v);
                        if (/^OK$/i.test(v)) {
                            return '<span style="color:green;">' + s + '</span>';
                        } else if (/Recover|Rebuild/i.test(v)) {
                            return '<span style="color:orange;font-weight:bold;">' + s + '</span>';
                        }
                        return '<span style="color:red;font-weight:bold;">' + s + '</span>';
                    },
                },
                { text: 'Disk', dataIndex: 'disk_name', width: 80, renderer: Ext.htmlEncode },
                { text: 'Mount', dataIndex: 'mount_points', flex: 1, renderer: Ext.htmlEncode },
                {
                    text: 'Media Errors',
                    dataIndex: 'media_errors',
                    width: 110,
                    renderer: function (v) {
                        if (!v) return '-';
                        var s = Ext.htmlEncode(v);
                        if (/None/i.test(v)) return s;
                        return '<span style="color:red;font-weight:bold;">' + s + '</span>';
                    },
                },
            ],
            emptyText: 'No logical drives detected.',
        });

        // Drives grid
        me.driveGrid = Ext.create('Ext.grid.Panel', {
            title: 'Physical Drives (S.M.A.R.T. Overview)',
            flex: 1,
            scrollable: true,
            store: {
                fields: [
                    'device', 'cciss_port', 'model', 'serial', 'capacity',
                    'firmware', 'health', 'temperature', 'power_on_hours',
                    'reallocated_sectors', 'grown_defect_list', 'rotation_rate',
                    'pending_sectors', 'offline_uncorrectable',
                    'reallocation_events', 'spin_retries', 'crc_errors',
                    // ssacli fields
                    'bay', 'port', 'box', 'array', 'status', 'interface_type',
                    'drive_type', 'controller_model', 'controller_slot',
                    'physicaldrive', 'logical_volumes', 'last_failure_reason',
                    'max_temperature', 'wwid',
                ],
                data: [],
            },
            columns: [
                {
                    text: 'Location',
                    dataIndex: 'physicaldrive',
                    width: 100,
                    hidden: true,  // shown when ssacli data available
                    renderer: Ext.htmlEncode,
                },
                {
                    text: 'Array',
                    dataIndex: 'array',
                    width: 55,
                    renderer: Ext.htmlEncode,
                },
                {
                    text: 'Bay',
                    dataIndex: 'bay',
                    width: 45,
                    renderer: Ext.htmlEncode,
                },
                {
                    text: 'Port',
                    dataIndex: 'cciss_port',
                    width: 55,
                    renderer: function (v) {
                        if (v === -1 || v === '-1') return '<span style="color:gray;">N/A</span>';
                        return 'cciss,' + Ext.htmlEncode(String(v));
                    },
                },
                { text: 'Model', dataIndex: 'model', width: 180, renderer: Ext.htmlEncode },
                { text: 'Serial', dataIndex: 'serial', width: 130, renderer: Ext.htmlEncode },
                { text: 'Capacity', dataIndex: 'capacity', width: 80, renderer: Ext.htmlEncode },
                {
                    text: 'Interface',
                    dataIndex: 'interface_type',
                    width: 70,
                    renderer: Ext.htmlEncode,
                },
                {
                    text: 'Type',
                    dataIndex: 'drive_type',
                    width: 80,
                    renderer: function (v) {
                        if (!v) return '-';
                        var s = Ext.htmlEncode(v);
                        if (/spare/i.test(v)) {
                            return '<span style="color:#1e90ff;font-weight:bold;">' + s + '</span>';
                        }
                        return s;
                    },
                },
                {
                    text: 'Health',
                    dataIndex: 'health',
                    width: 80,
                    renderer: function (v) {
                        var s = Ext.htmlEncode(v || 'UNKNOWN');
                        if (/PASSED|OK/i.test(v)) {
                            return '<span style="color:green;font-weight:bold;">' + s + '</span>';
                        } else if (/FAIL/i.test(v)) {
                            return '<span style="color:red;font-weight:bold;">' + s + '</span>';
                        } else if (/Rebuild/i.test(v)) {
                            return '<span style="color:orange;font-weight:bold;">' + s + '</span>';
                        }
                        return '<span style="color:orange;">' + s + '</span>';
                    },
                },
                {
                    text: 'Status',
                    dataIndex: 'status',
                    width: 100,
                    renderer: function (v, meta, rec) {
                        if (!v) return '-';
                        var s = Ext.htmlEncode(v);
                        var reason = rec.get('last_failure_reason');
                        if (reason) {
                            meta.tdAttr = 'data-qtip="' + Ext.htmlEncode(reason) + '"';
                        }
                        if (/^OK$/i.test(v)) {
                            return '<span style="color:green;">' + s + '</span>';
                        } else if (/Rebuild/i.test(v)) {
                            return '<span style="color:orange;font-weight:bold;">' + s + '</span>';
                        }
                        return '<span style="color:red;font-weight:bold;">' + s + '</span>';
                    },
                },
                { text: 'Temp', dataIndex: 'temperature', width: 60, renderer: Ext.htmlEncode },
                {
                    text: 'Power-On (h)',
                    dataIndex: 'power_on_hours',
                    width: 95,
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
                    dataIndex: 'grown_defect_list',
                    width: 60,
                    renderer: function (v, meta, rec) {
                        var val = v || rec.get('reallocated_sectors');
                        if (!val && val !== 0 && val !== '0') return '-';
                        var s = Ext.htmlEncode(String(val));
                        if (parseInt(val, 10) > 0) {
                            return '<span style="color:orange;font-weight:bold;">' + s + '</span>';
                        }
                        return s;
                    },
                },
                {
                    text: 'Pending',
                    dataIndex: 'pending_sectors',
                    width: 60,
                    renderer: function (v) {
                        if (!v && v !== 0 && v !== '0') return '-';
                        var s = Ext.htmlEncode(String(v));
                        if (parseInt(v, 10) > 0) {
                            return '<span style="color:red;font-weight:bold;">' + s + '</span>';
                        }
                        return s;
                    },
                },
                {
                    text: 'Offline',
                    dataIndex: 'offline_uncorrectable',
                    width: 55,
                    renderer: function (v) {
                        if (!v && v !== 0 && v !== '0') return '-';
                        var s = Ext.htmlEncode(String(v));
                        if (parseInt(v, 10) > 0) {
                            return '<span style="color:red;font-weight:bold;">' + s + '</span>';
                        }
                        return s;
                    },
                },
                {
                    text: 'CRC Err',
                    dataIndex: 'crc_errors',
                    width: 60,
                    hidden: true,
                    renderer: function (v) {
                        if (!v && v !== 0 && v !== '0') return '-';
                        var s = Ext.htmlEncode(String(v));
                        if (parseInt(v, 10) > 0) {
                            return '<span style="color:orange;font-weight:bold;">' + s + '</span>';
                        }
                        return s;
                    },
                },
                { text: 'RPM', dataIndex: 'rotation_rate', width: 70, renderer: Ext.htmlEncode, hidden: true },
            ],
            emptyText: 'No drives detected behind HP Smart Array controllers.',
            listeners: {
                itemdblclick: function (view, record) {
                    var port = record.get('cciss_port');
                    if (port === -1 || port === '-1') {
                        // Drive not reachable via smartctl (e.g. failed) — show info from ssacli
                        var reason = record.get('last_failure_reason');
                        var msg = 'This drive is not reachable via smartctl.';
                        if (record.get('status')) {
                            msg += '<br>Status: <b>' + Ext.htmlEncode(record.get('status')) + '</b>';
                        }
                        if (reason) {
                            msg += '<br>Reason: ' + Ext.htmlEncode(reason);
                        }
                        Ext.Msg.show({
                            title: 'Drive ' + Ext.htmlEncode(record.get('physicaldrive') || record.get('serial') || 'Unknown'),
                            message: msg,
                            icon: Ext.Msg.WARNING,
                            buttons: Ext.Msg.OK,
                        });
                        return;
                    }
                    Ext.create('PVE.SmartRaidMon.DriveDetailWindow', {
                        pveNode: nodename,
                        device: record.get('device'),
                        ccissPort: port,
                        title:
                            'S.M.A.R.T. Details — /dev/' +
                            record.get('device') +
                            ' cciss,' +
                            port,
                        autoShow: true,
                    });
                },
                itemcontextmenu: function (view, record, item, index, e) {
                    e.stopEvent();
                    var pd = record.get('physicaldrive');
                    var slot = record.get('controller_slot');
                    if (!pd || slot === undefined || slot === null) return;

                    var isSpare = /spare/i.test(record.get('drive_type') || '');
                    var menu = Ext.create('Ext.menu.Menu', {
                        items: [
                            {
                                text: 'Turn LED On',
                                iconCls: 'fa fa-lightbulb-o',
                                handler: function () {
                                    me.driveAction('led', slot, pd, 'on');
                                },
                            },
                            {
                                text: 'Turn LED Off',
                                iconCls: 'fa fa-circle-o',
                                handler: function () {
                                    me.driveAction('led', slot, pd, 'off');
                                },
                            },
                            '-',
                            {
                                text: isSpare ? 'Remove from Spare' : 'Set as Spare',
                                iconCls: isSpare ? 'fa fa-minus-circle' : 'fa fa-plus-circle',
                                handler: function () {
                                    var action = isSpare ? 'unspare' : 'spare';
                                    var msg = isSpare
                                        ? 'Remove drive ' + Ext.htmlEncode(pd) + ' from spare?'
                                        : 'Add drive ' + Ext.htmlEncode(pd) + ' as spare for all arrays?';
                                    Ext.Msg.confirm('Confirm', msg, function (btn) {
                                        if (btn === 'yes') {
                                            me.driveAction(action, slot, pd);
                                        }
                                    });
                                },
                            },
                        ],
                    });
                    menu.showAt(e.getXY());
                },
            },
        });

        // Status bar
        me.statusBar = Ext.create('Ext.toolbar.Toolbar', {
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
                        me.loadSummary(true);
                    },
                },
            ],
        });

        Ext.apply(me, {
            items: [me.controllerGrid, me.logicalDriveGrid, me.driveGrid, me.statusBar],
        });

        me.callParent();
        me.loadSummary();
    },

    loadSummary: function (force) {
        var me = this;
        var nodename = me.pveSelNode.data.node;
        var statusText = me.statusBar.getComponent('statusText');

        statusText.setText('Scanning controllers and drives...');

        var params = {};
        if (force) {
            params.force = 1;
        }

        Proxmox.Utils.API2Request({
            url: '/nodes/' + encodeURIComponent(nodename) + '/smartraidmon/summary',
            method: 'GET',
            params: params,
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

                // Load logical drives
                if (data.logical_drives && data.logical_drives.length > 0) {
                    me.logicalDriveGrid.getStore().loadData(data.logical_drives);
                    me.logicalDriveGrid.setVisible(true);
                } else {
                    me.logicalDriveGrid.getStore().removeAll();
                    me.logicalDriveGrid.setVisible(false);
                }

                // Load drives
                if (data.drives) {
                    me.driveGrid.getStore().loadData(data.drives);

                    // Show ssacli columns if data is present
                    var hasSSA = data.drives.some(function (d) { return !!d.physicaldrive; });
                    var cols = me.driveGrid.getColumns();
                    cols.forEach(function (col) {
                        if (col.dataIndex === 'physicaldrive') {
                            col.setVisible(hasSSA);
                        }
                    });

                    var total = data.drives.length;
                    var healthy = 0;
                    var failed = 0;
                    var rebuilding = 0;
                    var unknown = 0;

                    Ext.Array.each(data.drives, function (d) {
                        if (/PASSED|OK/i.test(d.health)) {
                            healthy++;
                        } else if (/FAIL/i.test(d.health) || /FAIL/i.test(d.status)) {
                            failed++;
                        } else if (/Rebuild/i.test(d.health) || /Rebuild/i.test(d.status)) {
                            rebuilding++;
                        } else {
                            unknown++;
                        }
                    });

                    var statusMsg =
                        total + ' drive(s) found — ' +
                        healthy + ' healthy';
                    if (rebuilding > 0) {
                        statusMsg += ', <span style="color:orange;font-weight:bold;">' +
                            rebuilding + ' rebuilding</span>';
                    }
                    if (failed > 0) {
                        statusMsg += ', <span style="color:red;font-weight:bold;">' +
                            failed + ' FAILED</span>';
                    }
                    if (unknown > 0) {
                        statusMsg += ', ' + unknown + ' unknown';
                    }

                    // Show rebuild progress from logical drives
                    if (data.logical_drives) {
                        Ext.Array.each(data.logical_drives, function (ld) {
                            if (ld.rebuild_progress !== undefined && ld.rebuild_progress !== null) {
                                statusMsg += ' | <span style="color:orange;">LD ' +
                                    ld.ld_id + ' rebuild: ' + ld.rebuild_progress + '%</span>';
                            }
                        });
                    }

                    // Show controller info from ssacli
                    if (data.controllers && data.controllers.length > 0) {
                        var ctrl = data.controllers[0];
                        var ctrlName = ctrl.controller_model || ctrl.model || '';
                        if (ctrlName && ctrlName !== 'LOGICAL VOLUME') {
                            statusMsg += ' | ' + Ext.htmlEncode(ctrlName);
                            if (ctrl.controller_slot !== undefined) {
                                statusMsg += ' Slot ' + ctrl.controller_slot;
                            }
                        }
                    }

                    // Show cache info
                    if (data.cached) {
                        statusMsg += ' | <span style="color:gray;">cached ' +
                            data.cache_age + 's ago</span>';
                    }

                    statusText.setText(statusMsg);
                } else {
                    statusText.setText('No drives found.');
                }
            },
        });
    },

    driveAction: function (action, slot, pd, extra) {
        var me = this;
        var nodename = me.pveSelNode.data.node;
        var params = {
            slot: slot,
            physicaldrive: pd,
        };
        if (action === 'led' && extra) {
            params.action = extra;
        }
        Proxmox.Utils.API2Request({
            url: '/nodes/' + encodeURIComponent(nodename) +
                 '/smartraidmon/' + action,
            method: 'POST',
            params: params,
            failure: function (response) {
                Ext.Msg.alert('Error',
                    'Action failed: ' + (response.htmlStatus || 'Unknown error'));
            },
            success: function () {
                me.loadSummary();
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
