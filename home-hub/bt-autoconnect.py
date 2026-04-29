#!/usr/bin/env python3
# bt-autoconnect.py
# Runs once at boot after BlueZ is ready.
# Connects all trusted BT devices and sets the first
# connected one as the default PipeWire audio sink.
#
# Location: ~/ArduinoApps/home-hub/bt-autoconnect.py
# Installed to: /usr/local/bin/bt-autoconnect.py by setup_for_bt_audio.sh
# Run by: bt-autoconnect.service (systemd user service)

import subprocess
import time
import sys

LOG_PREFIX = '[BT-AUTOCONNECT]'


def log(msg):
    print(f'{LOG_PREFIX} {msg}', flush=True)


def run(cmd, timeout=10):
    try:
        result = subprocess.run(
            cmd, shell=True,
            capture_output=True, text=True,
            timeout=timeout
        )
        return result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return '', 1
    except Exception as e:
        log(f'Command failed: {cmd} -- {e}')
        return '', 1


def get_trusted_devices():
    out, _ = run('bluetoothctl devices Trusted')
    devices = []
    for line in out.splitlines():
        parts = line.strip().split(' ', 2)
        if len(parts) >= 3 and parts[0] == 'Device':
            devices.append({'mac': parts[1], 'name': parts[2]})
    return devices


def is_connected(mac):
    out, _ = run(f'bluetoothctl info {mac}')
    return 'Connected: yes' in out


def connect_device(mac, name):
    log(f'Connecting: {name} ({mac})')
    out, code = run(f'bluetoothctl connect {mac}', timeout=15)
    if code == 0 or 'Connection successful' in out or 'Connected: yes' in out:
        log(f'Connected: {name}')
        return True
    log(f'Failed to connect: {name} -- {out}')
    return False


def get_pipewire_bt_sink(mac):
    mac_under = mac.replace(':', '_').lower()
    out, _ = run('wpctl status')
    for line in out.splitlines():
        if mac_under in line.lower() or 'bluez' in line.lower():
            parts = line.strip().split('.')
            if parts[0].strip().isdigit():
                return parts[0].strip()
    return None


def set_default_sink(sink_id, name):
    _, code = run(f'wpctl set-default {sink_id}')
    if code == 0:
        log(f'Set default audio sink: {name} (id={sink_id})')
        return True
    log(f'Failed to set default sink: {name}')
    return False


def wait_for_bluez(max_wait=30):
    log('Waiting for BlueZ...')
    for i in range(max_wait):
        out, code = run('bluetoothctl show')
        if code == 0 and 'Powered: yes' in out:
            log(f'BlueZ ready (after {i}s)')
            return True
        time.sleep(1)
    log('BlueZ did not become ready in time')
    return False


def wait_for_pipewire(max_wait=20):
    log('Waiting for PipeWire...')
    for i in range(max_wait):
        out, code = run('wpctl status')
        if code == 0 and 'Sinks' in out:
            log(f'PipeWire ready (after {i}s)')
            return True
        time.sleep(1)
    log('PipeWire did not become ready in time')
    return False


def main():
    log('Starting BT auto-connect')

    if not wait_for_bluez():
        log('Aborting - BlueZ not ready')
        sys.exit(1)

    if not wait_for_pipewire():
        log('Aborting - PipeWire not ready')
        sys.exit(1)

    time.sleep(3)

    devices = get_trusted_devices()

    if not devices:
        log('No trusted BT devices found - nothing to connect')
        sys.exit(0)

    log(f'Found {len(devices)} trusted device(s): {[d["name"] for d in devices]}')

    connected = []
    for device in devices:
        mac  = device['mac']
        name = device['name']
        if is_connected(mac):
            log(f'Already connected: {name}')
            connected.append(device)
            continue
        if connect_device(mac, name):
            time.sleep(2)
            connected.append(device)

    if not connected:
        log('No devices connected - keeping current default sink')
        sys.exit(0)

    primary = connected[0]
    for attempt in range(5):
        sink_id = get_pipewire_bt_sink(primary['mac'])
        if sink_id:
            set_default_sink(sink_id, primary['name'])
            break
        log(f'Sink not found yet, retrying ({attempt + 1}/5)...')
        time.sleep(2)
    else:
        out, _ = run('wpctl status')
        for line in out.splitlines():
            if 'bluez' in line.lower() or primary['name'].lower() in line.lower():
                parts = line.strip().split('.')
                if len(parts) >= 2 and parts[0].strip().isdigit():
                    set_default_sink(parts[0].strip(), primary['name'])
                    break
        else:
            log('Could not find BT sink in PipeWire - audio may route to HDMI')

    log(f'Done. Connected: {[d["name"] for d in connected]}')


if __name__ == '__main__':
    main()
