import os
import sys
import ctypes
import threading
import time
import json
from datetime import datetime

os.environ['GI_TYPELIB_PATH'] = '/app/typelibs'
os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = 'unix:path=/app/dbus.sock'

for lib in [
    'libm.so.6', 'libcap.so.2', 'libpcre2-8.so.0',
    'libselinux.so.1', 'libaudit.so.1', 'libcap-ng.so.0',
    'libexpat.so.1', 'libdbus-1.so.3', 'libapparmor.so.1',
    'libsystemd.so.0', 'libgirepository-2.0.so.0',
]:
    try:
        ctypes.CDLL(f'/app/wheels/{lib}')
    except Exception as e:
        print(f'[BLE_SUB] lib load failed {lib}: {e}', flush=True)

sys.path.insert(0, '/usr/lib/python3/dist-packages')

import dbus
import dbus.mainloop.glib
from gi.repository import GLib

SERVICE_UUID      = 'aa206b91-235b-42aa-b370-453a3feedf35'
WEIGHT_CHAR_UUID  = 'b9b25bb1-f2a9-4545-b48f-295ab2789f41'
DEVICE_NAME       = 'GasCylMonitor'
CONFIG_PATH       = '/app/config.json'

BLUEZ        = 'org.bluez'
ADAPTER_PATH = '/org/bluez/hci0'
DBUS_OM      = 'org.freedesktop.DBus.ObjectManager'
DBUS_PROP    = 'org.freedesktop.DBus.Properties'
GATT_CHAR    = 'org.bluez.GattCharacteristic1'
DEVICE_IFACE = 'org.bluez.Device1'


class BLESubscriber:
    def __init__(self, on_weight):
        self.on_weight      = on_weight
        self.bus            = None
        self.adapter        = None
        self.target_device  = None
        self.weight_char    = None
        self.scanning       = False
        self._loop          = None
        self._config        = {}

    def start(self):
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

        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        try:
            self.bus = dbus.SystemBus()
            print('[BLE_SUB] D-Bus connected', flush=True)
        except Exception as e:
            print(f'[BLE_SUB] D-Bus failed: {e}', flush=True)
            return

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
        self._loop = GLib.MainLoop()
        self._loop.run()

    def _start_scan(self):
        try:
            self.adapter.SetDiscoveryFilter(dbus.Dictionary({
                'UUIDs':     dbus.Array([SERVICE_UUID], signature='s'),
                'Transport': dbus.String('le')
            }, signature='sv'))
            self.adapter.StartDiscovery()
            self.scanning = True
            print(f'[BLE_SUB] Scanning for {DEVICE_NAME} ({SERVICE_UUID})', flush=True)
        except Exception as e:
            print(f'[BLE_SUB] Scan failed: {e}', flush=True)

    def _stop_scan(self):
        try:
            if self.scanning:
                self.adapter.StopDiscovery()
                self.scanning = False
                print('[BLE_SUB] Scan stopped', flush=True)
        except Exception as e:
            print(f'[BLE_SUB] Stop scan error: {e}', flush=True)

    def _interfaces_added(self, path, interfaces):
        if DEVICE_IFACE not in interfaces:
            return
        props = interfaces[DEVICE_IFACE]
        uuids = [str(u) for u in props.get('UUIDs', [])]
        name  = str(props.get('Name', 'Unknown'))
        if SERVICE_UUID in uuids:
            print(f'[BLE_SUB] Found: {name} at {path}', flush=True)
            self._stop_scan()
            GLib.idle_add(self._connect, path)

    def _connect(self, path):
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
            GLib.timeout_add(5000, lambda: self._start_scan() or False)
        return False

    def _find_characteristic(self):
        try:
            om      = dbus.Interface(self.bus.get_object(BLUEZ, '/'), DBUS_OM)
            objects = om.GetManagedObjects()
            for path, ifaces in objects.items():
                if GATT_CHAR not in ifaces:
                    continue
                uuid = str(ifaces[GATT_CHAR].get('UUID', ''))
                if uuid.lower() == WEIGHT_CHAR_UUID.lower():
                    print(f'[BLE_SUB] Found weight char at {path}', flush=True)
                    self.weight_char = path
                    self._subscribe_notify(path)
                    return False
            print('[BLE_SUB] Weight char not found -- retrying in 3s', flush=True)
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
        except Exception as e:
            print(f'[BLE_SUB] Subscribe failed: {e}', flush=True)

    def _on_notify(self, interface, changed, invalidated, path):
        if 'Value' not in changed:
            return
        try:
            raw_str = bytes(changed['Value']).decode('utf-8').strip()
            payload = json.loads(raw_str)
            grams   = float(payload['grams'])
            quality = str(payload['quality'])
            sigma   = float(payload['sigma'])
            hub_ts  = datetime.now().isoformat(timespec='seconds')
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
                GLib.timeout_add(5000, lambda: self._start_scan() or False)
