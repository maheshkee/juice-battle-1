import os
import sys
import ctypes
import threading
import time

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
        print(f'[BLE_CENTRAL] lib load failed {lib}: {e}', flush=True)

sys.path.insert(0, '/usr/lib/python3/dist-packages')

import dbus
import dbus.mainloop.glib
from gi.repository import GLib

SERVICE_UUID  = 'a01c0000-0000-0000-0000-000000000000'
URL_CHAR_UUID = 'a01c0001-0000-0000-0000-000000000000'
BLUEZ         = 'org.bluez'
ADAPTER_PATH  = '/org/bluez/hci0'
DBUS_OM       = 'org.freedesktop.DBus.ObjectManager'
DBUS_PROP     = 'org.freedesktop.DBus.Properties'
GATT_CHAR     = 'org.bluez.GattCharacteristic1'
DEVICE_IFACE  = 'org.bluez.Device1'


class BLECentral:
    def __init__(self, on_url_received):
        self.on_url_received = on_url_received
        self.bus = None
        self.adapter = None
        self.target_device = None
        self.url_char = None
        self.scanning = False
        self._loop = None

    def start(self):
        t = threading.Thread(target=self._run, daemon=True)
        t.start()
        print('[BLE_CENTRAL] Started', flush=True)

    def _run(self):
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        try:
            self.bus = dbus.SystemBus()
            print('[BLE_CENTRAL] D-Bus connected', flush=True)
        except Exception as e:
            print(f'[BLE_CENTRAL] D-Bus failed: {e}', flush=True)
            return

        adapter_obj = self.bus.get_object(BLUEZ, ADAPTER_PATH)
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
                'UUIDs': dbus.Array([SERVICE_UUID], signature='s'),
                'Transport': dbus.String('le')
            }, signature='sv'))
            self.adapter.StartDiscovery()
            self.scanning = True
            print(f'[BLE_CENTRAL] Scanning for {SERVICE_UUID}', flush=True)
        except Exception as e:
            print(f'[BLE_CENTRAL] Scan failed: {e}', flush=True)

    def _stop_scan(self):
        try:
            if self.scanning:
                self.adapter.StopDiscovery()
                self.scanning = False
                print('[BLE_CENTRAL] Scan stopped', flush=True)
        except Exception as e:
            print(f'[BLE_CENTRAL] Stop scan error: {e}', flush=True)

    def _interfaces_added(self, path, interfaces):
        if DEVICE_IFACE not in interfaces:
            return
        props = interfaces[DEVICE_IFACE]
        uuids = [str(u) for u in props.get('UUIDs', [])]
        name = str(props.get('Name', 'Unknown'))
        if SERVICE_UUID in uuids:
            print(f'[BLE_CENTRAL] Found: {name} at {path}', flush=True)
            self._stop_scan()
            GLib.idle_add(self._connect, path)

    def _connect(self, path):
    try:
        dev_obj = self.bus.get_object(BLUEZ, path)
        device = dbus.Interface(dev_obj, DEVICE_IFACE)

        # Remove device first if previously cached
        try:
            self.adapter.RemoveDevice(dbus.ObjectPath(path))
            time.sleep(1)
        except Exception:
            pass

        print(f'[BLE_CENTRAL] Connecting...', flush=True)
        device = dbus.Interface(self.bus.get_object(BLUEZ, path), DEVICE_IFACE)
        device.Connect()
        self.target_device = path
        print('[BLE_CENTRAL] Connected', flush=True)
        time.sleep(4)
        GLib.idle_add(self._find_characteristic)
    except Exception as e:
        print(f'[BLE_CENTRAL] Connect failed: {e}', flush=True)
        GLib.timeout_add(5000, lambda: self._start_scan() or False)
    return False

    def _find_characteristic(self):
        try:
            om = dbus.Interface(self.bus.get_object(BLUEZ, '/'), DBUS_OM)
            objects = om.GetManagedObjects()
            for path, ifaces in objects.items():
                if GATT_CHAR not in ifaces:
                    continue
                uuid = str(ifaces[GATT_CHAR].get('UUID', ''))
                if uuid.lower() == URL_CHAR_UUID.lower():
                    print(f'[BLE_CENTRAL] Found URL char at {path}', flush=True)
                    self.url_char = path
                    self._subscribe_notify(path)
                    self._read_url(path)
                    return False
            print('[BLE_CENTRAL] URL char not found — retrying in 3s', flush=True)
            GLib.timeout_add(3000, self._find_characteristic)
        except Exception as e:
            print(f'[BLE_CENTRAL] Find char error: {e}', flush=True)
        return False

    def _read_url(self, path):
        try:
            char = dbus.Interface(self.bus.get_object(BLUEZ, path), GATT_CHAR)
            value = char.ReadValue({})
            url = bytes(value).decode('utf-8').strip()
            print(f'[BLE_CENTRAL] Read URL: {url}', flush=True)
            if url:
                self.on_url_received(url)
        except Exception as e:
            print(f'[BLE_CENTRAL] Read failed: {e}', flush=True)

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
            print('[BLE_CENTRAL] Subscribed to notifications', flush=True)
        except Exception as e:
            print(f'[BLE_CENTRAL] Subscribe failed: {e}', flush=True)

    def _on_notify(self, interface, changed, invalidated, path):
        if 'Value' not in changed:
            return
        url = bytes(changed['Value']).decode('utf-8').strip()
        print(f'[BLE_CENTRAL] Notified URL: {url}', flush=True)
        if url:
            self.on_url_received(url)

    def _properties_changed(self, interface, changed, invalidated, path):
        if interface != DEVICE_IFACE:
            return
        if 'Connected' in changed and not bool(changed['Connected']):
            if path == self.target_device:
                print('[BLE_CENTRAL] Disconnected — resuming scan', flush=True)
                self.target_device = None
                self.url_char = None
                GLib.timeout_add(3000, lambda: self._start_scan() or False)
