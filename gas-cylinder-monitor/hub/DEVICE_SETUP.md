# Gas Cylinder Monitor — New Device Setup

Run these steps once on a new device, in order. All steps are idempotent — safe to re-run.

---

## Step 1 — Passwordless sudo (requires sudo once)

```bash
sudo bash hub/setup_sudoers.sh
```

This writes `/etc/sudoers.d/gas-cylinder-monitor` and grants NOPASSWD for:

| Command | Used by |
|---------|---------|
| `systemctl restart/stop/start bluetooth` | `deploy.sh` — resets BT adapter before each deploy |
| `systemctl restart/stop/start dbus-bridge-gas-cylinder-monitor.service` | `deploy.sh` — ensures fresh `dbus.sock` |
| `bluetoothctl` | `deploy.sh` — powers on BT adapter |
| `tee /etc/sudoers.d/gas-cylinder-monitor` | `setup_sudoers.sh` re-runs without sudo |
| `visudo`, `chmod 440 /etc/sudoers.d/gas-cylinder-monitor` | sudoers file validation and permissions |
| `/sbin/reboot` | HUB-WATCHDOG Level 3 — board reboot when BT adapter is unrecoverable |

Validates with `visudo -c` before keeping the file. Exits with error and removes the file on syntax failure.

After this step completes, all future `deploy.sh` and `setup_sudoers.sh` re-runs need no password.

To verify:

```bash
sudo cat /etc/sudoers.d/gas-cylinder-monitor
```

---

## Step 2 — Board setup

```bash
bash hub/setup.sh
```

This does (all idempotent — skips steps already done):

1. Installs system packages: `socat`, `libdbus-1-dev`, `libcairo2-dev`, `libgirepository-2.0-dev`
2. Builds Python wheels into `hub/wheels/`: `dbus-python`, `PyGObject`
3. Copies shared libraries from host into `hub/wheels/`
4. Copies GObject typelibs into `hub/typelibs/`
5. Creates, enables, and starts the `dbus-bridge-gas-cylinder-monitor.service` systemd service
6. Installs, enables, and starts the `gas-cylinder-watchdog.service` host watchdog (from `hub/gas-cylinder-watchdog.service`)
7. Copies `socket.io.min.js` from any existing app on the board (warns if not found)
8. Generates `hub/python/requirements.txt` from actual wheel filenames
9. Writes `~/.gas-cylinder-monitor-setup-done` sentinel (`deploy.sh` exits if this is missing)
10. Sets `gas-cylinder-monitor/hub` as the default App Lab app

### The dbus-bridge service (Step 5 detail)

`setup.sh` creates `/etc/systemd/system/dbus-bridge-gas-cylinder-monitor.service`:

```
[Unit]
Description=DBus Unix Bridge for gas-cylinder-monitor/hub
After=network.target

[Service]
User=arduino
ExecStartPre=/bin/rm -f <project>/dbus.sock
ExecStart=/usr/bin/socat \
    UNIX-LISTEN:<project>/dbus.sock,fork,reuseaddr,mode=0777,unlink-early \
    UNIX-CONNECT:/run/dbus/system_bus_socket
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

This bridges the host D-Bus system socket into `hub/dbus.sock` so the Docker container can reach BlueZ without running privileged. `deploy.sh` restarts this service before every deploy to guarantee a fresh socket.

To check the service manually:

```bash
systemctl status dbus-bridge-gas-cylinder-monitor.service
sudo journalctl -u dbus-bridge-gas-cylinder-monitor.service -n 30
```

---

## Step 3 — First deploy

```bash
bash hub/deploy.sh
```

---

## Everyday deploy (after code changes)

```bash
bash hub/deploy.sh
```

No password required after Step 1.

---

## Re-running setup

```bash
bash hub/setup.sh          # safe to re-run — skips already-done steps
bash hub/setup_sudoers.sh  # safe to re-run — no sudo needed after Step 1
```

---

## Auto-start on boot

`setup.sh` Step 10 sets the default app automatically. If it failed, run manually:

```bash
arduino-app-cli properties set default user:gas-cylinder-monitor/hub
```

Verify:

```bash
arduino-app-cli app list | grep gas-cylinder
```

Should show `DEFAULT` in the status column. After this, the hub starts on every power-on without needing `deploy.sh`.

---

## HUB-WATCHDOG reboot rule (pre-production gate)

The `/sbin/reboot` NOPASSWD rule is installed by `setup_sudoers.sh` (Step 1). It is needed by
HUB-WATCHDOG Level 3: when the BT adapter is unrecoverable, the Docker container writes
`hub/data/reboot.trigger` and the host watchdog service calls `sudo /sbin/reboot`.

Verify the rule is in place:

```bash
sudo grep reboot /etc/sudoers.d/gas-cylinder-monitor
```

Expected:

```
arduino ALL=(ALL) NOPASSWD: /sbin/reboot
```

### Host watchdog service (`gas-cylinder-watchdog.service`)

Installed by `setup.sh` Step 6. Watches `hub/data/restart.trigger` and `hub/data/reboot.trigger`
written by the Docker container's `watchdog.py`.

| Trigger file | Action |
|---|---|
| `hub/data/restart.trigger` | `systemctl restart bluetooth`, sleep 10, delete file |
| `hub/data/reboot.trigger` | `sudo /sbin/reboot`, delete file |

To check the service:

```bash
systemctl status gas-cylinder-watchdog
sudo journalctl -u gas-cylinder-watchdog -n 20
```

To re-run setup after a fresh clone (reinstalls the service if missing):

```bash
bash hub/setup.sh
```
