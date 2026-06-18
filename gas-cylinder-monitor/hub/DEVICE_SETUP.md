# Gas Cylinder Monitor — New Device Setup

## One-time setup (run once per device, with sudo)

```bash
sudo bash hub/setup_sudoers.sh
```

This installs passwordless sudo rules for the specific commands deploy.sh needs
(bluetooth restart, dbus-bridge restart). Nothing else is granted.

## Every deploy (no password required after setup)

```bash
bash hub/deploy.sh
```

## What setup_sudoers.sh does

- Writes `/etc/sudoers.d/gas-cylinder-monitor` with NOPASSWD rules for:
  - `systemctl restart/stop/start bluetooth`
  - `systemctl restart/stop/start dbus-bridge-gas-cylinder-monitor.service`
  - `bluetoothctl`
  - `tee /etc/sudoers.d/gas-cylinder-monitor` (allows re-running setup without sudo)
  - `visudo` and `chmod 440` for that file
- Validates the sudoers file with `visudo -c` before keeping it
- Sets permissions to `440` (required by sudo)

## Re-running setup

After the first run, setup_sudoers.sh can be re-run without sudo:

```bash
bash hub/setup_sudoers.sh
```
