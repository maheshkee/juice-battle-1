import sys
import os
import ctypes
import socket
import time
import threading
import datetime
import re
import json

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

BLUEZ_SERVICE_NAME           = 'org.bluez'
ADAPTER_IFACE                = 'org.bluez.Adapter1'
DEVICE_IFACE                 = 'org.bluez.Device1'
GATT_MANAGER_IFACE           = 'org.bluez.GattManager1'
GATT_SERVICE_IFACE           = 'org.bluez.GattService1'
GATT_CHRC_IFACE              = 'org.bluez.GattCharacteristic1'
LE_ADVERTISING_MANAGER_IFACE = 'org.bluez.LEAdvertisingManager1'
LE_ADVERTISEMENT_IFACE       = 'org.bluez.LEAdvertisement1'
DBUS_PROP_IFACE              = 'org.freedesktop.DBus.Properties'
DBUS_OM_IFACE                = 'org.freedesktop.DBus.ObjectManager'

ADAPTER_PATH  = '/org/bluez/hci0'
LAUNCHER_SOCK = '/app/launcher.sock'
MAX_HISTORY   = 20
TRUSTED_FILE  = '/app/trusted_devices.json'

PHONE_SVC_UUID = 'a00b0000-0000-0000-0000-000000000000'
PHONE_CMD_UUID = 'a00b0002-0000-0000-0000-000000000000'
PHONE_EVT_UUID = 'a00b0003-0000-0000-0000-000000000000'

ui           = WebUI()
led_state    = False
current_url  = None
current_mode = 'idle'
url_history  = []

bus          = None
is_scanning  = False
scan_results = {}
connected    = {}
trusted      = {}
discovering  = set()

adv_mgr_global  = None
adv_global      = None
gatt_mgr_global = None
evt_char_global = None


def now_str():
    return datetime.datetime.now().strftime("%H:%M:%S")

def log(message):
    print(message, flush=True)
    ui.send_message('log', {'message': message, 'time': now_str()})

def push_to_phone(event: str, payload: dict):
    global evt_char_global
    if evt_char_global and evt_char_global.notifying:
        msg = json.dumps({'event': event, **payload})
        evt_char_global.update_value(list(msg.encode('utf-8')))

def extract_video_id(url: str):
    patterns = [
        r'(?:v=)([A-Za-z0-9_-]{11})',
        r'(?:youtu\.be/)([A-Za-z0-9_-]{11})',
        r'(?:embed/)([A-Za-z0-9_-]{11})',
        r'(?:shorts/)([A-Za-z0-9_-]{11})',
    ]
    for p in patterns:
        m = re.search(p, url)
        if m:
            return m.group(1)
    return None

def is_youtube_url(url: str) -> bool:
    return 'youtube.com' in url or 'youtu.be' in url


def load_trusted():
    global trusted
    try:
        if os.path.exists(TRUSTED_FILE):
            with open(TRUSTED_FILE, 'r') as f:
                trusted = json.load(f)
            log(f'[TRUST] Loaded {len(trusted)} trusted device(s)')
    except Exception as e:
        log(f'[TRUST] Load failed: {e}')
        trusted = {}

def save_trusted():
    try:
        with open(TRUSTED_FILE, 'w') as f:
            json.dump(trusted, f)
    except Exception as e:
        log(f'[TRUST] Save failed: {e}')

def push_trusted():
    devices = [{'mac': mac, 'name': name} for mac, name in trusted.items()]
    ui.send_message('trusted_devices', {'devices': devices})
    push_to_phone('trusted_devices', {'devices': devices})


def launcher_send(cmd: str) -> str:
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect(LAUNCHER_SOCK)
        s.sendall((cmd + '\n').encode('utf-8'))
        response = s.recv(256).decode('utf-8').strip()
        s.close()
        return response
    except Exception as e:
        log(f'[LAUNCHER] Send failed ({cmd}): {e}')
        return 'error'

def launcher_ping() -> bool:
    return launcher_send('ping') == 'pong'


def set_mode(mode: str):
    global current_mode
    current_mode = mode
    log(f'[MODE] Switching to {mode}')
    ui.send_message('mode_update', {'mode': mode, 'time': now_str()})
    ui.send_message('display_cmd', {'cmd': 'set_mode', 'mode': mode})
    launcher_send(f'mode:{mode}')
    push_to_phone('mode_update', {'mode': mode, 'time': now_str()})

def handle_url(url: str):
    global current_url
    url = url.strip().replace('\x00', '').replace('\r', '').replace('\n', '')
    url = ''.join(c for c in url if 32 <= ord(c) < 127).strip()
    if not url:
        return
    if not is_youtube_url(url):
        log(f'[URL] Rejected - not a YouTube link: {url}')
        ui.send_message('url_rejected', {'url': url, 'reason': 'Not a YouTube link', 'time': now_str()})
        push_to_phone('url_rejected', {'url': url, 'reason': 'Not a YouTube link', 'time': now_str()})
        return
    video_id = extract_video_id(url)
    if not video_id:
        log(f'[URL] Rejected - could not extract video ID: {url}')
        ui.send_message('url_rejected', {'url': url, 'reason': 'Could not extract video ID', 'time': now_str()})
        push_to_phone('url_rejected', {'url': url, 'reason': 'Could not extract video ID', 'time': now_str()})
        return
    log(f'[URL] Received: {url}  (ID: {video_id})')
    current_url = url
    url_history.insert(0, {'url': url, 'video_id': video_id, 'time': now_str()})
    if len(url_history) > MAX_HISTORY:
        url_history.pop()
    ui.send_message('url_update', {'url': url, 'video_id': video_id, 'time': now_str()})
    ui.send_message('url_history', {'history': url_history})
    push_to_phone('url_update', {'url': url, 'video_id': video_id, 'time': now_str()})
    push_to_phone('url_history', {'history': url_history})
    threading.Thread(target=_play, args=(video_id,), daemon=True).start()

def _play(video_id: str):
    launcher_send(f'play:{video_id}')
    time.sleep(1)
    set_mode('youtube')
    ui.send_message('display_cmd', {'cmd': 'play', 'video_id': video_id})
    log(f'[PLAYER] Play sent: {video_id}')

def handle_player_cmd(cmd: str):
    log(f'[PLAYER] Command: {cmd}')
    if cmd == 'stop':
        ui.send_message('display_cmd', {'cmd': 'stop'})
        global current_mode
        current_mode = 'idle'
        ui.send_message('mode_update', {'mode': 'idle', 'time': now_str()})
        push_to_phone('mode_update', {'mode': 'idle', 'time': now_str()})
    elif cmd in ('clock', 'idle', 'youtube'):
        set_mode(cmd)
    else:
        ui.send_message('display_cmd', {'cmd': cmd})
    ui.send_message('player_state', {'cmd': cmd, 'time': now_str()})
    push_to_phone('player_state', {'cmd': cmd, 'time': now_str()})


def handle_phone_command(text: str):
    global led_state
    text = text.strip()
    log(f'[PHONE] Received: {text}')

    if text.startswith('YT:'):
        GLib.idle_add(handle_url, text[3:].strip())

    elif text.startswith('CMD:'):
        cmd = text[4:].strip()

        if cmd == 'LED_ON':
            led_state = True
            Bridge.call("set_led_state", True)
            log('[CMD] LED ON')
            ui.send_message('led_status', {'state': True, 'text': 'ON', 'time': now_str()})
            push_to_phone('led_status', {'state': True, 'time': now_str()})

        elif cmd == 'LED_OFF':
            led_state = False
            Bridge.call("set_led_state", False)
            log('[CMD] LED OFF')
            ui.send_message('led_status', {'state': False, 'text': 'OFF', 'time': now_str()})
            push_to_phone('led_status', {'state': False, 'time': now_str()})

        elif cmd == 'LED_TOGGLE':
            led_state = not led_state
            Bridge.call("set_led_state", led_state)
            log(f'[CMD] LED TOGGLE -> {"ON" if led_state else "OFF"}')
            ui.send_message('led_status', {'state': led_state, 'text': 'ON' if led_state else 'OFF', 'time': now_str()})
            push_to_phone('led_status', {'state': led_state, 'time': now_str()})

        elif cmd == 'MODE_IDLE':
            GLib.idle_add(set_mode, 'idle')
        elif cmd == 'MODE_YOUTUBE':
            GLib.idle_add(set_mode, 'youtube')
        elif cmd == 'MODE_CLOCK':
            GLib.idle_add(set_mode, 'clock')

        elif cmd == 'PLAYER_PAUSE':
            GLib.idle_add(handle_player_cmd, 'pause')
        elif cmd == 'PLAYER_RESUME':
            GLib.idle_add(handle_player_cmd, 'resume')
        elif cmd == 'PLAYER_STOP':
            GLib.idle_add(handle_player_cmd, 'stop')
        elif cmd == 'PLAYER_MUTE':
            GLib.idle_add(handle_player_cmd, 'mute')
        elif cmd == 'PLAYER_UNMUTE':
            GLib.idle_add(handle_player_cmd, 'unmute')

        elif cmd == 'SCAN_START':
            GLib.idle_add(start_scan)
        elif cmd == 'SCAN_STOP':
            GLib.idle_add(stop_scan)

        elif cmd.startswith('CONNECT:'):
            mac = cmd[8:].strip()
            if mac:
                connect_device(mac)

        elif cmd.startswith('DISCONNECT:'):
            mac = cmd[11:].strip()
            if mac:
                disconnect_device(mac)

        elif cmd.startswith('FORGET:'):
            mac = cmd[7:].strip()
            if mac:
                GLib.idle_add(forget_device, mac)

        elif cmd == 'GET_STATUS':
            _push_full_status_to_phone()

        else:
            log(f'[CMD] Unknown: {cmd}')

def _push_full_status_to_phone():
    push_to_phone('full_status', {
        'mode':        current_mode,
        'led':         led_state,
        'current_url': current_url,
        'history':     url_history,
        'scanning':    is_scanning,
        'scan_results': [
            {'mac': mac, 'name': d.get('name', ''), 'rssi': d.get('rssi', 0)}
            for mac, d in scan_results.items()
        ],
        'connected_devices': [
            {
                'mac':  mac,
                'name': d.get('name', mac),
                'characteristics': [
                    {'uuid': u, 'name': c.get('name', u[:8]), 'value': c.get('value', ''), 'flags': c.get('flags', [])}
                    for u, c in d.get('characteristics', {}).items()
                ]
            }
            for mac, d in connected.items()
        ],
        'trusted': [{'mac': mac, 'name': name} for mac, name in trusted.items()],
        'time': now_str(),
    })


def push_scan_results():
    devices = [
        {'mac': mac, 'name': d.get('name', ''), 'rssi': d.get('rssi', 0)}
        for mac, d in scan_results.items()
    ]
    ui.send_message('scan_results', {'devices': devices})
    push_to_phone('scan_results', {'devices': devices})

def push_connected_devices():
    devices = [
        {
            'mac':  mac,
            'name': d.get('name', mac),
            'characteristics': [
                {'uuid': uuid, 'name': c.get('name', uuid[:8]), 'value': c.get('value', ''), 'flags': c.get('flags', [])}
                for uuid, c in d.get('characteristics', {}).items()
            ]
        }
        for mac, d in connected.items()
    ]
    ui.send_message('connected_devices', {'devices': devices})
    push_to_phone('connected_devices', {'devices': devices})

def get_all_objects():
    try:
        mgr = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, '/'), DBUS_OM_IFACE)
        return mgr.GetManagedObjects()
    except Exception as e:
        log(f'[BLE] GetManagedObjects failed: {e}')
        return {}

def start_scan():
    global is_scanning
    if is_scanning:
        try:
            adapter_if = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, ADAPTER_PATH), ADAPTER_IFACE)
            adapter_if.StopDiscovery()
        except Exception:
            pass
        is_scanning = False
        time.sleep(0.5)
    try:
        adapter_if = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, ADAPTER_PATH), ADAPTER_IFACE)
        adapter_if.SetDiscoveryFilter(dbus.Dictionary({'Transport': dbus.String('le')}, signature='sv'))
        adapter_if.StartDiscovery()
        is_scanning = True
        log('[SCAN] Started BLE scan')
        ui.send_message('scan_status', {'scanning': True, 'time': now_str()})
        push_to_phone('scan_status', {'scanning': True, 'time': now_str()})
        threading.Timer(12.0, lambda: GLib.idle_add(stop_scan)).start()
    except Exception as e:
        log(f'[SCAN] Start failed: {e}')

def stop_scan():
    global is_scanning
    if not is_scanning:
        return
    try:
        adapter_if = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, ADAPTER_PATH), ADAPTER_IFACE)
        adapter_if.StopDiscovery()
        is_scanning = False
        log('[SCAN] Stopped BLE scan')
        ui.send_message('scan_status', {'scanning': False, 'time': now_str()})
        push_to_phone('scan_status', {'scanning': False, 'time': now_str()})
    except Exception as e:
        log(f'[SCAN] Stop failed: {e}')

def connect_device(mac: str):
    threading.Thread(target=_connect_device, args=(mac,), daemon=True).start()

def _connect_device(mac: str):
    dev_path = scan_results.get(mac, {}).get('path')
    if not dev_path:
        objects = get_all_objects()
        for path, ifaces in objects.items():
            if DEVICE_IFACE in ifaces:
                addr = str(ifaces[DEVICE_IFACE].get('Address', ''))
                if addr.upper() == mac.upper():
                    dev_path = path
                    break
    if not dev_path:
        log(f'[CONNECT] Device not found: {mac}')
        return
    try:
        dev_obj = bus.get_object(BLUEZ_SERVICE_NAME, dev_path)
        dev_if  = dbus.Interface(dev_obj, DEVICE_IFACE)
        props   = dbus.Interface(dev_obj, DBUS_PROP_IFACE)
        already = bool(props.Get(DEVICE_IFACE, 'Connected'))
        if not already:
            log(f'[CONNECT] Connecting to {mac}...')
            dev_if.Connect()
        name = ''
        try:
            name = str(props.Get(DEVICE_IFACE, 'Name'))
        except Exception:
            name = mac
        log(f'[CONNECT] Connected: {name} ({mac})')
        connected[mac] = {'name': name, 'path': dev_path, 'characteristics': {}}
        ui.send_message('device_connected', {'mac': mac, 'name': name, 'time': now_str()})
        push_to_phone('device_connected', {'mac': mac, 'name': name, 'time': now_str()})
        push_connected_devices()
        threading.Thread(target=_discover_characteristics, args=(mac, dev_path), daemon=True).start()
    except Exception as e:
        log(f'[CONNECT] Failed {mac}: {e}')
        ui.send_message('device_error', {'mac': mac, 'error': str(e), 'time': now_str()})
        push_to_phone('device_error', {'mac': mac, 'error': str(e), 'time': now_str()})

def _discover_characteristics(mac: str, dev_path: str):
    if mac in discovering:
        return
    discovering.add(mac)
    time.sleep(2)
    objects = get_all_objects()
    for path, ifaces in objects.items():
        if GATT_CHRC_IFACE not in ifaces:
            continue
        if not path.startswith(dev_path):
            continue
        props  = ifaces[GATT_CHRC_IFACE]
        uuid   = str(props.get('UUID', ''))
        flags  = [str(f) for f in props.get('Flags', [])]
        name   = _known_uuid_name(uuid)
        char_entry = {'uuid': uuid, 'name': name, 'flags': flags, 'value': '', 'path': path}
        connected[mac]['characteristics'][uuid] = char_entry
        if 'read' in flags:
            try:
                ch_if  = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, path), GATT_CHRC_IFACE)
                raw    = ch_if.ReadValue(dbus.Dictionary({}, signature='sv'))
                value  = _decode_value(uuid, bytes(raw))
                connected[mac]['characteristics'][uuid]['value'] = value
                log(f'[CHAR] {name} ({mac}): {value}')
            except Exception as e:
                log(f'[CHAR] Read failed {uuid[:8]}: {e}')
        if 'notify' in flags or 'indicate' in flags:
            try:
                ch_if = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, path), GATT_CHRC_IFACE)
                ch_if.StartNotify()
                bus.add_signal_receiver(
                    lambda iface, changed, inv, p=path, m=mac, u=uuid: _on_char_changed(m, u, iface, changed),
                    dbus_interface=DBUS_PROP_IFACE,
                    signal_name='PropertiesChanged',
                    path=path
                )
                log(f'[NOTIFY] Subscribed to {name} ({mac})')
            except Exception as e:
                log(f'[NOTIFY] Subscribe failed {uuid[:8]}: {e}')
    discovering.discard(mac)
    push_connected_devices()
    log(f'[DISCOVER] Done for {mac} - {len(connected[mac]["characteristics"])} characteristics')

def _on_char_changed(mac: str, uuid: str, interface: str, changed):
    if interface != GATT_CHRC_IFACE:
        return
    if 'Value' not in changed:
        return
    try:
        raw   = bytes(changed['Value'])
        value = _decode_value(uuid, raw)
        if mac in connected and uuid in connected[mac]['characteristics']:
            connected[mac]['characteristics'][uuid]['value'] = value
        name = _known_uuid_name(uuid)
        log(f'[NOTIFY] {name} ({mac}): {value}')
        ui.send_message('characteristic_update', {'mac': mac, 'uuid': uuid, 'name': name, 'value': value, 'time': now_str()})
        push_to_phone('characteristic_update', {'mac': mac, 'uuid': uuid, 'name': name, 'value': value, 'time': now_str()})
        push_connected_devices()
    except Exception as e:
        log(f'[NOTIFY] Parse failed: {e}')

def disconnect_device(mac: str):
    threading.Thread(target=_disconnect_device, args=(mac,), daemon=True).start()

def _disconnect_device(mac: str):
    dev = connected.get(mac)
    if not dev:
        return
    try:
        dev_if = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, dev['path']), DEVICE_IFACE)
        dev_if.Disconnect()
        log(f'[DISCONNECT] {dev["name"]} ({mac})')
    except Exception as e:
        log(f'[DISCONNECT] Failed {mac}: {e}')
    connected.pop(mac, None)
    ui.send_message('device_disconnected', {'mac': mac, 'time': now_str()})
    push_to_phone('device_disconnected', {'mac': mac, 'time': now_str()})
    push_connected_devices()

def forget_device(mac: str):
    trusted.pop(mac, None)
    save_trusted()
    push_trusted()
    log(f'[TRUST] Forgot {mac}')

def _known_uuid_name(uuid: str) -> str:
    known = {
        '00002a19': 'Battery Level',
        '00002a6e': 'Temperature',
        '00002a37': 'Heart Rate',
        '00002a29': 'Manufacturer',
        '00002a24': 'Model Number',
        '00002a25': 'Serial Number',
        '00002a27': 'Hardware Revision',
        '00002a26': 'Firmware Revision',
        '00002a6f': 'Humidity',
        '00002a6d': 'Pressure',
        '00002a00': 'Device Name',
        '00002a01': 'Appearance',
    }
    return known.get(uuid[:8].lower(), uuid[:8])

def _decode_value(uuid: str, raw: bytes) -> str:
    if not raw:
        return ''
    prefix = uuid[:8].lower()
    try:
        if prefix == '00002a19':
            return f'{raw[0]}%'
        if prefix == '00002a6e':
            val = int.from_bytes(raw[:2], 'little', signed=True) / 100.0
            return f'{val:.1f} C'
        if prefix == '00002a37':
            return f'{raw[1]} bpm'
        if prefix in ('00002a29', '00002a24', '00002a25', '00002a27', '00002a26', '00002a00'):
            return raw.decode('utf-8', errors='ignore').strip()
        try:
            return raw.decode('utf-8').strip()
        except Exception:
            return raw.hex()
    except Exception:
        return raw.hex()


class BLEObjectWatcher:
    def __init__(self, bus):
        bus.add_signal_receiver(self._interfaces_added,   dbus_interface=DBUS_OM_IFACE, signal_name='InterfacesAdded')
        bus.add_signal_receiver(self._interfaces_removed, dbus_interface=DBUS_OM_IFACE, signal_name='InterfacesRemoved')
        bus.add_signal_receiver(self._props_changed,      dbus_interface=DBUS_PROP_IFACE, signal_name='PropertiesChanged', arg0=DEVICE_IFACE, path_keyword='path')

    def _interfaces_added(self, path, interfaces):
        if DEVICE_IFACE not in interfaces:
            return
        props = interfaces[DEVICE_IFACE]
        mac   = str(props.get('Address', ''))
        name  = str(props.get('Name', mac))
        rssi  = int(props.get('RSSI', 0))
        if not mac:
            return
        scan_results[mac] = {'name': name, 'rssi': rssi, 'path': path}
        push_scan_results()
        if mac in trusted and mac not in connected:
            log(f'[AUTO] Reconnecting trusted: {name} ({mac})')
            threading.Timer(1.0, lambda m=mac: connect_device(m)).start()

    def _interfaces_removed(self, path, interfaces):
        if DEVICE_IFACE not in interfaces:
            return
        for mac, d in list(scan_results.items()):
            if d.get('path') == path:
                scan_results.pop(mac, None)
        push_scan_results()

    def _props_changed(self, interface, changed, invalidated, path):
        if interface != DEVICE_IFACE:
            return
        rssi = changed.get('RSSI')
        name = changed.get('Name')
        for mac, d in scan_results.items():
            if d.get('path') == path:
                if rssi is not None: scan_results[mac]['rssi'] = int(rssi)
                if name is not None: scan_results[mac]['name'] = str(name)
        push_scan_results()
        if 'Connected' in changed:
            for mac, d in list(connected.items()):
                if d.get('path') == path and not bool(changed['Connected']):
                    log(f'[BLE] Disconnected: {d["name"]} ({mac})')
                    connected.pop(mac, None)
                    ui.send_message('device_disconnected', {'mac': mac, 'time': now_str()})
                    push_to_phone('device_disconnected', {'mac': mac, 'time': now_str()})
                    push_connected_devices()

def _autoconnect_existing():
    if not trusted:
        return
    try:
        objects = get_all_objects()
        for path, ifaces in objects.items():
            if DEVICE_IFACE not in ifaces:
                continue
            props = ifaces[DEVICE_IFACE]
            mac   = str(props.get('Address', ''))
            name  = str(props.get('Name', mac))
            if mac and mac in trusted and mac not in connected:
                log(f'[AUTO] Found trusted in cache: {name} ({mac})')
                connect_device(mac)
    except Exception as e:
        log(f'[AUTO] Check existing failed: {e}')


class PhoneAdvertisement(dbus.service.Object):
    def __init__(self, bus, index):
        self.path = f'/org/bluez/hci0/advertisement{index}'
        self.bus  = bus
        dbus.service.Object.__init__(self, bus, self.path)

    @dbus.service.method(DBUS_PROP_IFACE, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        if interface != LE_ADVERTISEMENT_IFACE:
            raise dbus.exceptions.DBusException('org.bluez.Error.InvalidArgs')
        return {
            'Type':           dbus.String('peripheral'),
            'ServiceUUIDs':   dbus.Array([PHONE_SVC_UUID], signature='s'),
            'LocalName':      dbus.String('BLE-Hub'),
            'IncludeTxPower': dbus.Boolean(True),
            'Discoverable':   dbus.Boolean(True),
        }

    @dbus.service.method(LE_ADVERTISEMENT_IFACE)
    def Release(self):
        log('[ADV] Released')


class PhoneApplication(dbus.service.Object):
    def __init__(self, bus):
        self.path     = '/org/bluez/hci0/phoneapp'
        self.services = []
        dbus.service.Object.__init__(self, bus, self.path)

    def add_service(self, svc):
        self.services.append(svc)

    @dbus.service.method(DBUS_OM_IFACE, out_signature='a{oa{sa{sv}}}')
    def GetManagedObjects(self):
        resp = {}
        for svc in self.services:
            resp[svc.path] = {GATT_SERVICE_IFACE: {'UUID': dbus.String(svc.uuid), 'Primary': dbus.Boolean(True)}}
            for c in svc.chars:
                resp[c.path] = {GATT_CHRC_IFACE: c.get_props()}
        return resp


class PhoneService(dbus.service.Object):
    def __init__(self, bus):
        self.path  = '/org/bluez/hci0/phoneapp/service0'
        self.uuid  = PHONE_SVC_UUID
        self.chars = []
        dbus.service.Object.__init__(self, bus, self.path)


class PhoneCmdChar(dbus.service.Object):
    def __init__(self, bus, service):
        self.path    = '/org/bluez/hci0/phoneapp/service0/char0'
        self.uuid    = PHONE_CMD_UUID
        self.service = service
        self.value   = dbus.Array([], signature='y')
        dbus.service.Object.__init__(self, bus, self.path)

    def get_props(self):
        return {
            'Service': dbus.ObjectPath(self.service.path),
            'UUID':    dbus.String(self.uuid),
            'Flags':   dbus.Array(['write', 'write-without-response'], signature='s'),
        }

    @dbus.service.method(GATT_CHRC_IFACE, in_signature='aya{sv}')
    def WriteValue(self, value, options):
        text = bytes(value).decode('utf-8', errors='ignore')
        self.value = value
        handle_phone_command(text)


class PhoneEvtChar(dbus.service.Object):
    def __init__(self, bus, service):
        self.path      = '/org/bluez/hci0/phoneapp/service0/char1'
        self.uuid      = PHONE_EVT_UUID
        self.service   = service
        self.value     = dbus.Array([], signature='y')
        self.notifying = False
        dbus.service.Object.__init__(self, bus, self.path)

    def get_props(self):
        return {
            'Service':   dbus.ObjectPath(self.service.path),
            'UUID':      dbus.String(self.uuid),
            'Flags':     dbus.Array(['notify'], signature='s'),
            'Notifying': dbus.Boolean(self.notifying),
        }

    @dbus.service.method(GATT_CHRC_IFACE)
    def StartNotify(self):
        if self.notifying:
            return
        self.notifying = True
        log('[PHONE] Notify started')
        GLib.idle_add(_push_full_status_to_phone)

    @dbus.service.method(GATT_CHRC_IFACE)
    def StopNotify(self):
        self.notifying = False
        log('[PHONE] Notify stopped')

    @dbus.service.signal(DBUS_PROP_IFACE, signature='sa{sv}as')
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    def update_value(self, value):
        self.value = dbus.Array(value, signature='y')
        self.PropertiesChanged(GATT_CHRC_IFACE, {'Value': self.value}, [])


def ble_main():
    global bus, adv_mgr_global, adv_global, gatt_mgr_global, evt_char_global

    print('[BLE] dbus.sock exists:', os.path.exists('/app/dbus.sock'))
    os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = 'unix:path=/app/dbus.sock'

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    try:
        bus = dbus.SystemBus()
        print('[BLE] SystemBus connected!')
    except Exception as e:
        print(f'[BLE] SystemBus failed: {e}')
        return

    BLEObjectWatcher(bus)
    load_trusted()
    GLib.idle_add(_autoconnect_existing)
    GLib.idle_add(start_scan)

    try:
        adapter_obj     = bus.get_object(BLUEZ_SERVICE_NAME, ADAPTER_PATH)
        gatt_mgr_global = dbus.Interface(adapter_obj, GATT_MANAGER_IFACE)
        adv_mgr_global  = dbus.Interface(adapter_obj, LE_ADVERTISING_MANAGER_IFACE)

        phone_app = PhoneApplication(bus)
        phone_svc = PhoneService(bus)
        cmd_char  = PhoneCmdChar(bus, phone_svc)
        evt_char  = PhoneEvtChar(bus, phone_svc)
        phone_svc.chars = [cmd_char, evt_char]
        phone_app.add_service(phone_svc)
        evt_char_global = evt_char

        gatt_mgr_global.RegisterApplication(
            dbus.ObjectPath(phone_app.path), {},
            reply_handler=lambda: log('[PHONE] GATT app registered'),
            error_handler=lambda e: log(f'[PHONE] GATT registration failed: {e}')
        )

        adv_global = PhoneAdvertisement(bus, 0)
        adv_mgr_global.RegisterAdvertisement(
            dbus.ObjectPath(adv_global.path), {},
            reply_handler=lambda: log('[PHONE] Advertising as BLE-Hub'),
            error_handler=lambda e: log(f'[PHONE] Advertising failed: {e}')
        )
    except Exception as e:
        log(f'[PHONE] Peripheral setup failed: {e}')

    log('=' * 50)
    log(' BLE Hub Started')
    log('=' * 50)
    log('Central:    scanning for sensors/devices')
    log('Peripheral: advertising as BLE-Hub for phone')
    log('=' * 50)

    GLib.MainLoop().run()


def on_send_url(client, data):
    url = (data or {}).get('url', '')
    GLib.idle_add(handle_url, url)

def on_player_cmd(client, data):
    cmd = (data or {}).get('cmd', '')
    GLib.idle_add(handle_player_cmd, cmd)

def on_set_mode(client, data):
    mode = (data or {}).get('mode', 'idle')
    GLib.idle_add(set_mode, mode)

def on_scan_start(client, data):
    GLib.idle_add(start_scan)

def on_scan_stop(client, data):
    GLib.idle_add(stop_scan)

def on_connect_device(client, data):
    mac = (data or {}).get('mac', '')
    if mac:
        connect_device(mac)

def on_disconnect_device(client, data):
    mac = (data or {}).get('mac', '')
    if mac:
        disconnect_device(mac)

def on_forget_device(client, data):
    mac = (data or {}).get('mac', '')
    if mac:
        GLib.idle_add(forget_device, mac)

def on_toggle_led(client, data):
    global led_state
    led_state = not led_state
    Bridge.call("set_led_state", led_state)
    log(f'[LED] {"ON" if led_state else "OFF"}')
    push_to_phone('led_status', {'state': led_state, 'time': now_str()})

def on_player_event(client, data):
    state = (data or {}).get('state', '')
    log(f'[PLAYER] Event: {state}')

def on_get_initial_state(client, data):
    ui.send_message('initial_state', {
        'mode':        current_mode,
        'current_url': current_url,
        'history':     url_history,
        'scanning':    is_scanning,
        'scan_results': [
            {'mac': mac, 'name': d.get('name', ''), 'rssi': d.get('rssi', 0)}
            for mac, d in scan_results.items()
        ],
        'connected_devices': [
            {
                'mac':  mac,
                'name': d.get('name', mac),
                'characteristics': [
                    {'uuid': u, 'name': c.get('name', u[:8]), 'value': c.get('value', ''), 'flags': c.get('flags', [])}
                    for u, c in d.get('characteristics', {}).items()
                ]
            }
            for mac, d in connected.items()
        ],
        'trusted': [{'mac': mac, 'name': name} for mac, name in trusted.items()],
    }, client)

ui.on_message('send_url',          on_send_url)
ui.on_message('player_cmd',        on_player_cmd)
ui.on_message('set_mode',          on_set_mode)
ui.on_message('scan_start',        on_scan_start)
ui.on_message('scan_stop',         on_scan_stop)
ui.on_message('connect_device',    on_connect_device)
ui.on_message('disconnect_device', on_disconnect_device)
ui.on_message('forget_device',     on_forget_device)
ui.on_message('toggle_led',        on_toggle_led)
ui.on_message('player_event',      on_player_event)
ui.on_message('get_initial_state', on_get_initial_state)

if launcher_ping():
    log('[LAUNCHER] Connected to chromium-launcher')
else:
    log('[LAUNCHER] WARNING - chromium-launcher not reachable')

threading.Thread(target=ble_main, daemon=True).start()
App.run()