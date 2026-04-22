import sys
import os
import ctypes
import threading
import datetime
import time

os.environ['GI_TYPELIB_PATH'] = '/app/typelibs'

for lib in [
    'libm.so.6',
    'libcap.so.2',
    'libpcre2-8.so.0',
    'libselinux.so.1',
    'libaudit.so.1',
    'libcap-ng.so.0',
    'libexpat.so.1',
    'libdbus-1.so.3',
    'libapparmor.so.1',
    'libsystemd.so.0',
    'libgirepository-2.0.so.0',
]:
    try:
        ctypes.CDLL(f'/app/wheels/{lib}')
    except Exception as e:
        print(f'[LIB] Failed {lib}: {e}')

sys.path.insert(0, '/usr/lib/python3/dist-packages')

import dbus
import dbus.mainloop.glib
from gi.repository import GLib
from arduino.app_utils import App, Bridge
from arduino.app_bricks.web_ui import WebUI

BLUEZ_SERVICE_NAME = 'org.bluez'
DBUS_PROP_IFACE    = 'org.freedesktop.DBus.Properties'
DBUS_OM_IFACE      = 'org.freedesktop.DBus.ObjectManager'
DEVICE_IFACE       = 'org.bluez.Device1'
GATT_CHRC_IFACE    = 'org.bluez.GattCharacteristic1'

TARGET_NAME  = 'PIR-ESP32'
MOTION_UUID  = 'a00c0001-0000-0000-0000-000000000000'

motion_active   = False
last_event_time = 'Never'
total           = 0
events          = []

ui = WebUI()


def push_update():
    ui.send_message('motion_update', {
        'motion':  motion_active,
        'time':    last_event_time,
        'status':  'DETECTED' if motion_active else 'CLEAR',
        'total':   total,
        'events':  list(reversed(events[-20:]))
    })


def on_motion_received(state: bool):
    global motion_active, last_event_time, total
    motion_active   = state
    last_event_time = datetime.datetime.now().strftime("%H:%M:%S")
    if state:
        total += 1
    events.append({
        'time':  last_event_time,
        'state': 'DETECTED' if state else 'CLEAR',
        'count': total
    })
    if len(events) > 50:
        events.pop(0)
    print(f'[RX] Motion {"DETECTED" if state else "CLEAR"} at {last_event_time}')
    Bridge.call("set_motion_led", state)
    GLib.idle_add(push_update)


def on_client_connect(sid):
    ui.send_message('motion_update', {
        'motion':  motion_active,
        'time':    last_event_time,
        'status':  'DETECTED' if motion_active else 'CLEAR',
        'total':   total,
        'events':  list(reversed(events[-20:]))
    }, sid)


def ble_client_main():
    print('[BLE] dbus.sock exists:', os.path.exists('/app/dbus.sock'))
    os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = 'unix:path=/app/dbus.sock'

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    try:
        bus = dbus.SystemBus()
        print('[BLE] SystemBus connected')
    except Exception as e:
        print(f'[BLE] SystemBus failed: {e}')
        return

    adapter_obj   = bus.get_object(BLUEZ_SERVICE_NAME, '/org/bluez/hci0')
    adapter_iface = dbus.Interface(adapter_obj, 'org.bluez.Adapter1')

    def find_target():
        om      = dbus.Interface(
            bus.get_object(BLUEZ_SERVICE_NAME, '/'), DBUS_OM_IFACE)
        objects = om.GetManagedObjects()
        for path, ifaces in objects.items():
            if DEVICE_IFACE in ifaces:
                name = str(ifaces[DEVICE_IFACE].get('Name', ''))
                if name == TARGET_NAME:
                    return path
        return None

    def subscribe(device_path):
        om      = dbus.Interface(
            bus.get_object(BLUEZ_SERVICE_NAME, '/'), DBUS_OM_IFACE)
        objects = om.GetManagedObjects()
        for path, ifaces in objects.items():
            if GATT_CHRC_IFACE in ifaces:
                uuid = str(ifaces[GATT_CHRC_IFACE].get('UUID', ''))
                if uuid.lower() == MOTION_UUID.lower():
                    print(f'[BLE] Found motion characteristic at {path}')
                    char_obj   = bus.get_object(BLUEZ_SERVICE_NAME, path)
                    char_iface = dbus.Interface(char_obj, GATT_CHRC_IFACE)
                    char_iface.StartNotify()
                    print('[BLE] Subscribed to motion notifications')

                    def on_props_changed(interface, changed, invalidated):
                        if interface != GATT_CHRC_IFACE:
                            return
                        if 'Value' in changed:
                            val   = bytes(changed['Value'])
                            state = bool(val[0]) if val else False
                            on_motion_received(state)

                    bus.add_signal_receiver(
                        on_props_changed,
                        dbus_interface=DBUS_PROP_IFACE,
                        signal_name='PropertiesChanged',
                        path=path
                    )
                    return True
        return False

    def connect_loop():
        print(f'[BLE] Scanning for {TARGET_NAME}...')
        ui.send_message('ble_status', {
            'connected': False,
            'message':   f'Scanning for {TARGET_NAME}...'
        })
        try:
            adapter_iface.StartDiscovery()
        except Exception as e:
            print(f'[BLE] StartDiscovery: {e}')

        for attempt in range(30):
            time.sleep(2)
            device_path = find_target()
            if device_path:
                print(f'[BLE] Found {TARGET_NAME} at {device_path}')
                ui.send_message('ble_status', {
                    'connected': False,
                    'message':   f'Found {TARGET_NAME} — connecting...'
                })
                try:
                    adapter_iface.StopDiscovery()
                except:
                    pass
                device_obj   = bus.get_object(BLUEZ_SERVICE_NAME, device_path)
                device_iface = dbus.Interface(device_obj, DEVICE_IFACE)
                try:
                    device_iface.Connect()
                    print(f'[BLE] Connected to {TARGET_NAME}')
                    time.sleep(2)
                    if subscribe(device_path):
                        print('[BLE] Ready — waiting for motion events from ESP32')
                        ui.send_message('ble_status', {
                            'connected': True,
                            'message':   f'Connected to {TARGET_NAME}'
                        })
                        return
                except Exception as e:
                    print(f'[BLE] Connect failed: {e}')

        print(f'[BLE] Could not find {TARGET_NAME} after 30 attempts')
        ui.send_message('ble_status', {
            'connected': False,
            'message':   f'Could not find {TARGET_NAME}'
        })

    threading.Thread(target=connect_loop, daemon=True).start()
    GLib.MainLoop().run()


ui.on_connect(on_client_connect)

threading.Thread(target=ble_client_main, daemon=True).start()

App.run()