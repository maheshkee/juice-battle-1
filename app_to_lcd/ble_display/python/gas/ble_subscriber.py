import os
import threading
import time
import json
import subprocess
from datetime import datetime

import dbus
from gi.repository import GLib

SERVICE_UUID      = 'aa206b91-235b-42aa-b370-453a3feedf35'
WEIGHT_CHAR_UUID  = 'b9b25bb1-f2a9-4545-b48f-295ab2789f41'
LOG_CHAR_UUID     = 'd7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c'
CMD_CHAR_UUID     = 'c8a2f1e3-4d6b-4a7c-8e9f-1b2d3e4f5a6b'
DEVICE_NAME       = 'GasCylMonitor'
CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'gas_config.json')

BLUEZ        = 'org.bluez'
ADAPTER_PATH = '/org/bluez/hci0'
DBUS_OM      = 'org.freedesktop.DBus.ObjectManager'
DBUS_PROP    = 'org.freedesktop.DBus.Properties'
GATT_CHAR    = 'org.bluez.GattCharacteristic1'
DEVICE_IFACE = 'org.bluez.Device1'


class BLESubscriber:
    def __init__(self, on_weight, on_log_line=None, on_connected=None, on_disconnected=None):
        self.on_weight           = on_weight
        self.on_log_line         = on_log_line
        self.on_connected        = on_connected
        self.on_disconnected     = on_disconnected
        self.cmd_char            = None  # path to command characteristic for write_command()
        self._connecting         = False  # guard against duplicate connect attempts
        self.bus                 = None
        self.adapter             = None
        self.target_device       = None
        self.weight_char         = None
        self.scanning            = False
        self._loop               = None
        self._config             = {}
        self.last_boot_used_tare = False  # True if TARE was sent this connect

    def start(self, bus, scan_trigger=None):
        self.bus = bus
        self._scan_trigger = scan_trigger
        t = threading.Thread(target=self._run, daemon=True)
        t.start()
        print('[BLE_SUB] Started', flush=True)

    def _run(self):
        # Load config
        try:
            with open(CONFIG_PATH) as f:
                self._config = json.load(f)
            print(f'[BLE_SUB] Config loaded: device={self._config.get("device_name")} '
                  f'service={self._config.get("service_uuid")}', flush=True)
            if self._config.get('device_address'):
                print(f'[BLE_SUB] Cached MAC: {self._config["device_address"]} '
                      f'(hint only - discovery always by UUID filter)', flush=True)
        except Exception as e:
            print(f'[BLE_SUB] Config load failed: {e} -- using defaults', flush=True)

        adapter_obj  = self.bus.get_object(BLUEZ, ADAPTER_PATH)
        self.adapter = dbus.Interface(adapter_obj, 'org.bluez.Adapter1')

        self.bus.add_signal_receiver(
            self._interfaces_added,
            dbus_interface=DBUS_OM,
            signal_name='InterfacesAdded'
        )
        self.bus.add_signal_receiver(
            self._properties_changed,
            dbus_interface=DBUS_PROP,
            signal_name='PropertiesChanged',
            path_keyword='path'
        )

        self._start_scan()
        GLib.idle_add(self._check_known_devices)

    def _start_scan(self):
        # Do not start a new scan -- the BLE Hub main.py scan is already running.
        # Just register signal listener and check already-known devices.
        # GasCylMonitor will appear in InterfacesAdded when the existing scan finds it.
        self.scanning = True
        print(f'[BLE_SUB] Listening for {DEVICE_NAME} on existing scan', flush=True)
        GLib.idle_add(self._check_known_devices)
        GLib.timeout_add(30000, self._periodic_check)

    def _periodic_check(self):
        if not self._connecting and self.target_device is None:
            print('[BLE_SUB] Periodic check for GasCylMonitor...', flush=True)
            # trigger a fresh scan so gas node appears in InterfacesAdded
            if self._scan_trigger:
                self._scan_trigger()
            self._check_known_devices()
        return True

    def _stop_scan(self):
        # Nothing to stop -- we didn't start the scan
        self.scanning = False

    def _check_known_devices(self):
        try:
            om = dbus.Interface(
                self.bus.get_object(BLUEZ, '/'), DBUS_OM)
            objects = om.GetManagedObjects()
            for path, ifaces in objects.items():
                if DEVICE_IFACE not in ifaces:
                    continue
                props = ifaces[DEVICE_IFACE]
                name = str(props.get('Name', ''))
                if name == DEVICE_NAME:
                    print(f'[BLE_SUB] Found cached: {name} at {path}',
                          flush=True)
                    self._stop_scan()
                    GLib.idle_add(self._connect, path)
                    return False
        except Exception as e:
            print(f'[BLE_SUB] Known device check error: {e}', flush=True)
        return False

    def _interfaces_added(self, path, interfaces):
        if DEVICE_IFACE not in interfaces:
            return
        props = interfaces[DEVICE_IFACE]
        uuids = [str(u) for u in props.get('UUIDs', [])]
        name  = str(props.get('Name', 'Unknown'))
        if name == DEVICE_NAME:
            print(f'[BLE_SUB] Found: {name} at {path}', flush=True)
            self._stop_scan()
            GLib.idle_add(self._connect, path)

    def _connect(self, path):
        if self._connecting:
            print('[BLE_SUB] Connect already in progress — ignoring duplicate', flush=True)
            return False
        self._connecting = True
        try:
            dev_obj = self.bus.get_object(BLUEZ, path)
            device  = dbus.Interface(dev_obj, DEVICE_IFACE)
            print('[BLE_SUB] Connecting...', flush=True)
            device.Connect()
            self.target_device = path
            print('[BLE_SUB] Connected', flush=True)
            time.sleep(4)
            GLib.idle_add(self._find_characteristic)
        except Exception as e:
            print(f'[BLE_SUB] Connect failed: {e}', flush=True)
            self._connecting = False
            GLib.timeout_add(5000, lambda: self._start_scan() or False)
        return False

    def _find_characteristic(self):
        try:
            om      = dbus.Interface(self.bus.get_object(BLUEZ, '/'), DBUS_OM)
            objects = om.GetManagedObjects()
            found_weight = None
            found_log    = None
            found_cmd    = None
            for path, ifaces in objects.items():
                if GATT_CHAR not in ifaces:
                    continue
                uuid = str(ifaces[GATT_CHAR].get('UUID', '')).lower()
                if uuid == WEIGHT_CHAR_UUID.lower():
                    found_weight = path
                elif uuid == LOG_CHAR_UUID.lower():
                    found_log = path
                elif uuid == CMD_CHAR_UUID.lower():
                    found_cmd = path
            if found_weight and found_log and found_cmd:
                print(f'[BLE_SUB] Found weight char at {found_weight}', flush=True)
                print(f'[BLE_SUB] Found log char at {found_log}', flush=True)
                print(f'[BLE_SUB] Found cmd char at {found_cmd}', flush=True)
                self.cmd_char = found_cmd
                self._subscribe_notify(found_weight)
                self._subscribe_log_notify(found_log)
            else:
                missing = []
                if not found_weight: missing.append('weight')
                if not found_log:    missing.append('log')
                if not found_cmd:    missing.append('cmd')
                print(f'[BLE_SUB] Chars not found yet: {missing} -- retrying in 3s', flush=True)
                GLib.timeout_add(3000, self._find_characteristic)
        except Exception as e:
            print(f'[BLE_SUB] Find char error: {e}', flush=True)
        return False

    def _subscribe_notify(self, path):
        try:
            char = dbus.Interface(self.bus.get_object(BLUEZ, path), GATT_CHAR)
            char.StartNotify()
            self.bus.add_signal_receiver(
                self._on_notify,
                dbus_interface=DBUS_PROP,
                signal_name='PropertiesChanged',
                path=path,
                path_keyword='path'
            )
            print('[BLE_SUB] Subscribed to weight notifications', flush=True)
            if self.on_connected:
                mac = str(self.target_device).split('/')[-1] \
                          .replace('dev_', '').replace('_', ':')
                self.on_connected(DEVICE_NAME, mac)
            self._send_tare_commands()
        except Exception as e:
            print(f'[BLE_SUB] Subscribe failed: {e}', flush=True)

    def _subscribe_log_notify(self, path):
        try:
            char = dbus.Interface(self.bus.get_object(BLUEZ, path), GATT_CHAR)
            char.StartNotify()
            self.bus.add_signal_receiver(
                self._on_log_notify,
                dbus_interface=DBUS_PROP,
                signal_name='PropertiesChanged',
                path=path,
                path_keyword='path'
            )
            print('[BLE_SUB] Subscribed to log notifications', flush=True)
        except Exception as e:
            print(f'[BLE_SUB] Log subscribe failed: {e}', flush=True)

    def _on_log_notify(self, interface, changed, invalidated, path):
        if 'Value' not in changed:
            return
        try:
            line = bytes(changed['Value']).decode('utf-8')
            if self.on_log_line:
                self.on_log_line(line)
        except Exception as e:
            print(f'[BLE_SUB] Log notify parse error: {e}', flush=True)

    def _on_notify(self, interface, changed, invalidated, path):
        if 'Value' not in changed:
            return
        try:
            raw_str = bytes(changed['Value']).decode('utf-8').strip()
            payload = json.loads(raw_str)
            grams   = float(payload['grams'])
            quality = str(payload['quality'])
            sigma   = float(payload['sigma'])
            hub_ts  = subprocess.run(
                ['date', '+%d %b %Y  %H:%M:%S'],
                capture_output=True, text=True
            ).stdout.strip()
            print(f'[HUB] grams={grams} quality={quality} sigma={sigma} ts={hub_ts}',
                  flush=True)
            self.on_weight(grams, quality, sigma, hub_ts)
        except Exception as e:
            print(f'[BLE_SUB] Notify parse error: {e}', flush=True)

    def _properties_changed(self, interface, changed, invalidated, path):
        if interface != DEVICE_IFACE:
            return
        if 'Connected' in changed and not bool(changed['Connected']):
            if path == self.target_device:
                print('[BLE_SUB] Disconnected -- resuming scan in 5s', flush=True)
                self.target_device = None
                self.weight_char   = None
                self._connecting   = False
                if self.on_disconnected:
                    self.on_disconnected()
                GLib.timeout_add(5000, lambda: self._start_scan() or False)

    def _send_tare_commands(self):
        try:
            with open(CONFIG_PATH) as f:
                cfg = json.load(f)
        except Exception as e:
            print(f'[BLE_SUB] _send_tare_commands: config read failed: {e}', flush=True)
            return

        cylinder_state = cfg.get('cylinder_state', 'UNINSTALLED')
        cal_factor     = cfg.get('cal_factor')
        steel_g        = cfg.get('steel_g')
        tare_raw       = cfg.get('tare_raw')

        # Protective check: steel_g + tare_raw both non-null means a valid measurement
        # session exists on disk. Always skip tare to preserve it — cylinder_state in
        # memory cannot override this, because cylinder_state may not reflect persisted
        # reality after a hub restart.
        if steel_g is not None and tare_raw is not None:
            if cal_factor is None:
                print('[BLE_SUB] PROTECTIVE_SKIP: steel_g+tare_raw present but cal_factor'
                      ' missing in config — cannot send SKIP_TARE+SET_CAL', flush=True)
                return
            threading.Timer(1.0, lambda: self.write_command('SKIP_TARE')).start()
            threading.Timer(2.0,
                lambda cf=cal_factor: self.write_command(f'SET_CAL:{cf:.4f}')).start()
            self.last_boot_used_tare = False
            print(f'[BLE_SUB] PROTECTIVE_SKIP: sent SKIP_TARE + SET_CAL:{cal_factor:.4f} '
                  f'(steel_g={steel_g:.1f}g + tare_raw present in config — valid session,'
                  f' TARE suppressed regardless of cylinder_state={cylinder_state})', flush=True)
            return

        # steel_g is null — no valid measurement session exists, safe to apply
        # the cylinder_state-based decision below.
        if cylinder_state == 'UNINSTALLED':
            threading.Timer(1.0, lambda: self.write_command('TARE')).start()
            self.last_boot_used_tare = True
            if cal_factor is not None:
                threading.Timer(2.0,
                    lambda cf=cal_factor: self.write_command(f'SET_CAL:{cf:.4f}')).start()
            print(f'[BLE_SUB] sent TARE + SET_CAL:{cal_factor} '
                  f'(steel_g null in config — no valid session, cylinder_state=UNINSTALLED)', flush=True)
        else:
            if cal_factor is None:
                print('[BLE_SUB] cal_factor missing in config — cannot send SKIP_TARE+SET_CAL',
                      flush=True)
                return
            threading.Timer(1.0, lambda: self.write_command('SKIP_TARE')).start()
            threading.Timer(2.0,
                lambda cf=cal_factor: self.write_command(f'SET_CAL:{cf:.4f}')).start()
            self.last_boot_used_tare = False
            print(f'[BLE_SUB] sent SKIP_TARE + SET_CAL:{cal_factor:.4f} '
                  f'(steel_g null, cylinder_state={cylinder_state})', flush=True)

    def write_command(self, cmd):
        # Writes ASCII command string to node command characteristic.
        # cmd must include trailing newline e.g. "DUMP_LOG\n"
        if self.cmd_char is None:
            print(f'[BLE_SUB] write_command: cmd char not ready', flush=True)
            return
        try:
            char = dbus.Interface(
                self.bus.get_object(BLUEZ, self.cmd_char), GATT_CHAR)
            cmd_clean = cmd.strip()
            char.WriteValue(
                dbus.Array([dbus.Byte(b) for b in cmd_clean.encode('utf-8')],
                           signature='y'),
                dbus.Dictionary({}, signature='sv')
            )
            print(f'[BLE_SUB] sent command: {cmd_clean}', flush=True)
        except Exception as e:
            print(f'[BLE_SUB] write_command failed: {e}', flush=True)
