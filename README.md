# PVE Smart RAID Monitor

A Proxmox VE 8.x plugin that adds a **GUI panel** for monitoring S.M.A.R.T. data on drives behind **HP Smart Array (CCISS/HPSA)** controllers.

Uses `smartctl -a /dev/sdX -d cciss,N` to query each drive and presents the results directly in the Proxmox web interface.

## Features

- **Auto-detection** of HP Smart Array controllers via sysfs (`hpsa` / `cciss` drivers)
- **Drive probing** — automatically discovers all drives behind each controller (cciss,0 through cciss,127)
- **Health overview** — color-coded PASSED / FAILED / UNKNOWN status for every drive
- **S.M.A.R.T. attributes** — full ATA and SAS/SCSI attribute table with failure highlighting
- **Self-test log** viewer
- **Raw smartctl output** tab for full diagnostic detail
- **Temperature**, **power-on hours**, and **reallocated sector** quick-view columns
- Integrates as a node-level tab in the PVE web UI ("Smart Array Monitor")

## Screenshots

> *The plugin adds a "Smart Array Monitor" tab under each node in the Proxmox web UI.*

| View | Description |
|------|-------------|
| **Overview** | Controller list + drive grid with health, temperature, hours |
| **Detail popup** | Double-click a drive → full S.M.A.R.T. attributes, self-tests, raw output |

## Requirements

- **Proxmox VE 8.0** or later
- **smartmontools** (`smartctl` ≥ 7.0)
- HP Smart Array controller with `hpsa` or `cciss` kernel driver
- Root access for installation

## Quick Install (Development)

```bash
# On your Proxmox VE host:
git clone https://github.com/youruser/pve-smartraidmon.git
cd pve-smartraidmon
chmod +x install.sh uninstall.sh
sudo ./install.sh
```

The install script will:
1. Install the Perl API module to `/usr/share/perl5/PVE/API2/`
2. Install the smartctl scanner to `/usr/libexec/pve-smartraidmon/`
3. Install the JavaScript GUI to `/usr/share/pve-manager/js/`
4. Inject a `<script>` tag into the PVE index template
5. Restart `pveproxy`

After installation, reload the Proxmox web UI and navigate to any node — you'll see the **"Smart Array Monitor"** tab.

## Build Debian Package

```bash
# Install build dependencies
sudo apt-get install debhelper dpkg-dev

# Build the .deb
make deb

# Install
sudo dpkg -i ../pve-smartraidmon_1.0.0-1_all.deb
```

## Uninstall

```bash
# If installed via install.sh:
sudo ./uninstall.sh

# If installed via .deb:
sudo apt-get remove pve-smartraidmon
```

## Project Structure

```
pve-smartraidmon/
├── Makefile                          # Build targets (install, deb, clean)
├── install.sh                        # Quick dev install script
├── uninstall.sh                      # Removal script
├── debian/                           # Debian packaging
│   ├── control                       # Package metadata
│   ├── changelog                     # Version history
│   ├── rules                         # Build rules
│   ├── postinst                      # Post-install hook (patches PVE index)
│   ├── postrm                        # Post-remove hook (cleans up)
│   ├── compat                        # Debhelper compat level
│   └── copyright                     # License (AGPL-3.0+)
└── src/
    ├── PVE/API2/SmartRaidMon.pm      # Perl API backend (REST endpoints)
    ├── bin/smart-raid-scan            # Perl smartctl wrapper/parser
    ├── www/SmartRaidMon.js           # ExtJS GUI (drives grid, detail popup)
    └── pve-api-hook.pl               # API route registration
```

## How It Works

### Backend

1. **Controller detection** — Scans `/sys/block/sd*/device/driver` symlinks for `hpsa` or `cciss` drivers
2. **Drive probing** — Runs `smartctl -i /dev/sdX -d cciss,N` for N=0..127, stops when no more drives respond
3. **Health query** — Runs `smartctl -H -A /dev/sdX -d cciss,N` for quick health + key attributes
4. **Detail query** — Runs `smartctl -a /dev/sdX -d cciss,N` for full attribute dump

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api2/json/nodes/{node}/smartraidmon` | API index |
| GET | `/api2/json/nodes/{node}/smartraidmon/summary` | Full summary (controllers + drives) |
| GET | `/api2/json/nodes/{node}/smartraidmon/controllers` | List controllers |
| GET | `/api2/json/nodes/{node}/smartraidmon/drives` | List drives with health |
| GET | `/api2/json/nodes/{node}/smartraidmon/drives/{dev}/{port}` | Full S.M.A.R.T. detail |

### Frontend

The ExtJS panel integrates into PVE's node view as a tab. It shows:
- **Controller grid** — detected HP Smart Array controllers
- **Drive grid** — all drives with inline health/temp/hours columns
- **Detail window** (double-click) — tabbed view with parsed attributes, self-tests, and raw output

## Troubleshooting

### No controllers detected
- Verify your controller uses the `hpsa` or `cciss` driver: `ls -la /sys/block/sd*/device/driver`
- Ensure the drives appear as `/dev/sdX` block devices

### smartctl errors
- Confirm smartmontools is installed: `smartctl --version`
- Test manually: `smartctl -i /dev/sda -d cciss,0`
- Some controllers need `smartctl -a /dev/sgN -d cciss,N` — if your setup differs, adjust the scan script

### GUI not showing
- Check the script tag was injected: `grep SmartRaidMon /usr/share/pve-manager/index.html.tpl`
- Restart pveproxy: `systemctl restart pveproxy`
- Clear browser cache and reload

## License

AGPL-3.0+ — See [debian/copyright](debian/copyright) for details.
