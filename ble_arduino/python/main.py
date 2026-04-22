import sys
import os
import ctypes
import subprocess
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
        print(f'[LIB] Loaded {lib}')
    except Exception as e:
        print(f'[LIB] Failed {lib}: {e}')

sys.path.insert(0, '/usr/lib/python3/dist-packages')

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib
from arduino.app_utils import App, Bridge
from arduino.app_bricks.web_ui import WebUI
import random
import datetime
import threading

BLUEZ_SERVICE_NAME = 'org.bluez'
GATT_MANAGER_IFACE = 'org.bluez.GattManager1'
GATT_SERVICE_IFACE = 'org.bluez.GattService1'
GATT_CHRC_IFACE = 'org.bluez.GattCharacteristic1'
DBUS_PROP_IFACE = 'org.freedesktop.DBus.Properties'
DBUS_OM_IFACE = 'org.freedesktop.DBus.ObjectManager'
LE_ADVERTISEMENT_IFACE = 'org.bluez.LEAdvertisement1'
LE_ADVERTISING_MANAGER_IFACE = 'org.bluez.LEAdvertisingManager1'
DEVICE_IFACE = 'org.bluez.Device1'

ui = WebUI()
led_state = False
is_advertising = False
adv_mgr_global = None
adv_global = None

def log(message):
    print(message)
    ui.send_message('log', {
        'message': message,
        'time': datetime.datetime.now().strftime("%H:%M:%S")
    })

def sensor_update(value):
    ui.send_message('sensor_update', {
        'value': value,
        'time': datetime.datetime.now().strftime("%H:%M:%S")
    })

def command_update(text):
    ui.send_message('command_update', {
        'text': text,
        'time': datetime.datetime.now().strftime("%H:%M:%S")
    })

def timestamp_update(ts):
    ui.send_message('timestamp_update', {
        'timestamp': ts,
        'time': datetime.datetime.now().strftime("%H:%M:%S")
    })

def adv_status_update(is_adv):
    ui.send_message('adv_status', {
        'advertising': is_adv,
        'time': datetime.datetime.now().strftime("%H:%M:%S")
    })

def device_status_update(connected, name=None, mac=None):
    ui.send_message('device_status', {
        'connected': connected,
        'name': name,
        'mac': mac,
        'time': datetime.datetime.now().strftime("%H:%M:%S")
    })

def start_advertising():
    global is_advertising, adv_mgr_global, adv_global
    if is_advertising:
        log('[ADV] Already advertising')
        return
    try:
        adv_mgr_global.RegisterAdvertisement(
            dbus.ObjectPath(adv_global.path), {},
            reply_handler=lambda: (log('✓ Advertising started'), adv_status_update(True)),
            error_handler=lambda e: log(f'✗ Advertising failed: {e}')
        )
        is_advertising = True
    except Exception as e:
        log(f'[ERROR] Start advertising: {e}')

def stop_advertising():
    global is_advertising, adv_mgr_global, adv_global
    if not is_advertising:
        log('[ADV] Not advertising')
        return
    try:
        adv_mgr_global.UnregisterAdvertisement(
            dbus.ObjectPath(adv_global.path),
            reply_handler=lambda: (log('✓ Advertising stopped'), adv_status_update(False)),
            error_handler=lambda e: log(f'✗ Stop advertising failed: {e}')
        )
        is_advertising = False
    except Exception as e:
        log(f'[ERROR] Stop advertising: {e}')


class DeviceMonitor:
    def __init__(self, bus):
        self.bus = bus
        bus.add_signal_receiver(
            self.interfaces_added,
            dbus_interface=DBUS_OM_IFACE,
            signal_name='InterfacesAdded'
        )
        bus.add_signal_receiver(
            self.interfaces_removed,
            dbus_interface=DBUS_OM_IFACE,
            signal_name='InterfacesRemoved'
        )
        bus.add_signal_receiver(
            self.properties_changed,
            dbus_interface=DBUS_PROP_IFACE,
            signal_name='PropertiesChanged',
            arg0=DEVICE_IFACE,
            path_keyword='path'
        )

    def interfaces_added(self, path, interfaces):
        pass

    def interfaces_removed(self, path, interfaces):
        pass

    def properties_changed(self, interface, changed, invalidated, path):
        if interface != DEVICE_IFACE:
            return
        try:
            obj = self.bus.get_object(BLUEZ_SERVICE_NAME, path)
            props = dbus.Interface(obj, DBUS_PROP_IFACE)
            name = ''
            mac = path
            try:
                name = str(props.Get(DEVICE_IFACE, 'Name'))
            except:
                pass
            try:
                mac = str(props.Get(DEVICE_IFACE, 'Address'))
            except:
                pass
            connected = False
            try:
                connected = bool(props.Get(DEVICE_IFACE, 'Connected'))
            except:
                pass
        except:
            name = ''
            mac = path
            connected = False

        display = name if name else mac
        if 'Connected' in changed or 'Name' in changed:
            if connected:
                log(f'[BLE] Device connected: {display}')
                device_status_update(True, name=name if name else None, mac=mac)
            elif 'Connected' in changed and not connected:
                log(f'[BLE] Device disconnected: {display}')
                device_status_update(False)


class Advertisement(dbus.service.Object):
    def __init__(self, bus, index):
        self.path = '/org/bluez/hci0/advertisement' + str(index)
        self.bus = bus
        self.ad_type = 'peripheral'
        self.service_uuids = ['a00b0000-0000-0000-0000-000000000000']
        self.local_name = 'BLE'
        self.include_tx_power = True
        dbus.service.Object.__init__(self, bus, self.path)

    @dbus.service.method(DBUS_PROP_IFACE, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        if interface != LE_ADVERTISEMENT_IFACE:
            raise dbus.exceptions.DBusException('org.freedesktop.DBus.Error.InvalidArgs')
        return {
            'Type': dbus.String(self.ad_type),
            'ServiceUUIDs': dbus.Array(self.service_uuids, signature='s'),
            'LocalName': dbus.String(self.local_name),
            'IncludeTxPower': dbus.Boolean(self.include_tx_power),
            'Discoverable': dbus.Boolean(True)
        }

    @dbus.service.method(LE_ADVERTISEMENT_IFACE)
    def Release(self):
        log('[Advertisement] Released')


class Application(dbus.service.Object):
    def __init__(self, bus):
        self.path = '/org/bluez/hci0/app'
        self.services = []
        dbus.service.Object.__init__(self, bus, self.path)

    def add_service(self, service):
        self.services.append(service)

    @dbus.service.method(DBUS_OM_IFACE, out_signature='a{oa{sa{sv}}}')
    def GetManagedObjects(self):
        response = {}
        for service in self.services:
            response[service.path] = {GATT_SERVICE_IFACE: service.get_service_properties()}
            for char in service.characteristics:
                response[char.path] = {GATT_CHRC_IFACE: char.get_char_properties()}
        return response


class Service(dbus.service.Object):
    def __init__(self, bus, index, uuid):
        self.bus = bus
        self.uuid = uuid
        self.path = '/org/bluez/hci0/service' + str(index)
        self.characteristics = []
        dbus.service.Object.__init__(self, bus, self.path)

    def add_characteristic(self, characteristic):
        self.characteristics.append(characteristic)

    def get_service_properties(self):
        return {
            'UUID': dbus.String(self.uuid),
            'Primary': dbus.Boolean(True)
        }


class Characteristic(dbus.service.Object):
    def __init__(self, bus, index, uuid, flags, service):
        self.bus = bus
        self.uuid = uuid
        self.flags = flags
        self.service = service
        self.path = '/org/bluez/hci0/service0/char' + str(index)
        self.value = dbus.Array([], signature=dbus.Signature('y'))
        self.notifying = False
        dbus.service.Object.__init__(self, bus, self.path)

    def get_char_properties(self):
        return {
            'Service': dbus.ObjectPath(self.service.path),
            'UUID': dbus.String(self.uuid),
            'Flags': dbus.Array(self.flags, signature='s'),
            'Notifying': dbus.Boolean(self.notifying)
        }

    @dbus.service.method(GATT_CHRC_IFACE, in_signature='a{sv}', out_signature='ay')
    def ReadValue(self, options):
        return self.value

    @dbus.service.method(GATT_CHRC_IFACE, in_signature='aya{sv}')
    def WriteValue(self, value, options):
        decoded = bytes(value).decode('utf-8', errors='ignore')
        self.value = value

    @dbus.service.method(GATT_CHRC_IFACE)
    def StartNotify(self):
        if self.notifying:
            return
        self.notifying = True

    @dbus.service.method(GATT_CHRC_IFACE)
    def StopNotify(self):
        self.notifying = False

    @dbus.service.signal(DBUS_PROP_IFACE, signature='sa{sv}as')
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    def update_value(self, value):
        self.value = dbus.Array(value, signature='y')
        self.PropertiesChanged(GATT_CHRC_IFACE, {'Value': self.value}, [])


class RandomSensorCharacteristic(Characteristic):
    def __init__(self, bus, index, service):
        Characteristic.__init__(self, bus, index,
                               'a00b0001-0000-0000-0000-000000000000',
                               ['read'], service)

    @dbus.service.method(GATT_CHRC_IFACE, in_signature='a{sv}', out_signature='ay')
    def ReadValue(self, options):
        value = random.randint(0, 100)
        self.value = dbus.Array([value], signature='y')
        log(f'[SENSOR READ] Random number: {value}')
        sensor_update(value)
        return self.value


class TextCommandCharacteristic(Characteristic):
    def __init__(self, bus, index, service):
        Characteristic.__init__(self, bus, index,
                               'a00b0002-0000-0000-0000-000000000000',
                               ['write', 'write-without-response'], service)

    @dbus.service.method(GATT_CHRC_IFACE, in_signature='aya{sv}')
    def WriteValue(self, value, options):
        text = bytes(value).decode('utf-8', errors='ignore')
        log(f"[COMMAND] Phone sent: '{text}'")
        command_update(text)
        self.value = value


class TimestampCharacteristic(Characteristic):
    def __init__(self, bus, index, service):
        Characteristic.__init__(self, bus, index,
                               'a00b0003-0000-0000-0000-000000000000',
                               ['notify'], service)
        self.notifier = None

    def _send_timestamp(self):
        while self.notifying:
            ts = datetime.datetime.now().strftime("%H:%M:%S")
            self.update_value(list(ts.encode('utf-8')))
            log(f'[NOTIFY] Sent timestamp: {ts}')
            timestamp_update(ts)
            time.sleep(5)

    @dbus.service.method(GATT_CHRC_IFACE)
    def StartNotify(self):
        if self.notifying:
            return
        log('[NOTIFY START] Timestamp characteristic')
        self.notifying = True
        self.notifier = threading.Thread(target=self._send_timestamp, daemon=True)
        self.notifier.start()

    @dbus.service.method(GATT_CHRC_IFACE)
    def StopNotify(self):
        log('[NOTIFY STOP] Timestamp characteristic')
        self.notifying = False


def ble_main():
    global adv_mgr_global, adv_global, is_advertising

    print('[BLE] dbus.sock exists:', os.path.exists('/app/dbus.sock'))
    os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = 'unix:path=/app/dbus.sock'

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    try:
        bus = dbus.SystemBus()
        print('[BLE] SystemBus connected!')
    except Exception as e:
        print(f'[BLE] SystemBus failed: {e}')
        return

    DeviceMonitor(bus)

    adapter_path = '/org/bluez/hci0'

    try:
        adapter_obj = bus.get_object(BLUEZ_SERVICE_NAME, adapter_path)
        gatt_mgr = dbus.Interface(adapter_obj, GATT_MANAGER_IFACE)
        adv_mgr_global = dbus.Interface(adapter_obj, LE_ADVERTISING_MANAGER_IFACE)
    except Exception as e:
        log(f'[ERROR] Could not access Bluetooth adapter: {e}')
        return

    app = Application(bus)
    service = Service(bus, 0, 'a00b0000-0000-0000-0000-000000000000')
    service.add_characteristic(RandomSensorCharacteristic(bus, 0, service))
    service.add_characteristic(TextCommandCharacteristic(bus, 1, service))
    service.add_characteristic(TimestampCharacteristic(bus, 2, service))
    app.add_service(service)

    try:
        gatt_mgr.RegisterApplication(
            dbus.ObjectPath(app.path), {},
            reply_handler=lambda: log('✓ GATT application registered'),
            error_handler=lambda e: log(f'✗ GATT registration failed: {e}')
        )
    except Exception as e:
        log(f'[ERROR] Registering GATT app: {e}')
        return

    adv_global = Advertisement(bus, 0)
    try:
        adv_mgr_global.RegisterAdvertisement(
            dbus.ObjectPath(adv_global.path), {},
            reply_handler=lambda: (log('✓ Advertisement registered'), adv_status_update(True)),
            error_handler=lambda e: log(f'✗ Advertisement failed: {e}')
        )
        is_advertising = True
    except Exception as e:
        log(f'[ERROR] Registering advertisement: {e}')
        return

    log('=' * 50)
    log(' BLE GATT Server Started')
    log('=' * 50)
    log('Device Name : BLE')
    log('Service UUID: a00b0000-0000-0000-0000-000000000000')
    log('Char 1 - Random Sensor (Read)  : a00b0001-...')
    log('Char 2 - Text Command  (Write) : a00b0002-...')
    log('Char 3 - Timestamp     (Notify): a00b0003-...')
    log('=' * 50)
    log('Open nRF Connect and scan for BLE...')

    mainloop = GLib.MainLoop()
    mainloop.run()


def on_start_adv(client, data):
    print('[WebUI] Received start_adv from browser')
    GLib.idle_add(start_advertising)

def on_stop_adv(client, data):
    print('[WebUI] Received stop_adv from browser')
    GLib.idle_add(stop_advertising)

def on_toggle_led(client, data):
    global led_state
    led_state = not led_state
    Bridge.call("set_led_state", led_state)
    ui.send_message('led_status', {
        'state': led_state,
        'text': 'ON' if led_state else 'OFF',
        'time': time.strftime("%H:%M:%S")
    })
    print(f'[LED] State changed to: {"ON" if led_state else "OFF"}')

def on_get_initial_state(client, data):
    ui.send_message('led_status', {
        'state': led_state,
        'text': 'ON' if led_state else 'OFF',
        'time': time.strftime("%H:%M:%S")
    }, client)

ui.on_message('start_adv', on_start_adv)
ui.on_message('stop_adv', on_stop_adv)
ui.on_message('toggle_led', on_toggle_led)
ui.on_message('get_initial_state', on_get_initial_state)

t = threading.Thread(target=ble_main, daemon=True)
t.start()

App.run()