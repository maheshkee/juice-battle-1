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
    'libm.so.6', 'libcap.so.2', 'libpcre2-8.so.0', 'libselinux.so.1',
    'libaudit.so.1', 'libcap-ng.so.0', 'libexpat.so.1', 'libdbus-1.so.3',
    'libapparmor.so.1', 'libsystemd.so.0', 'libgirepository-2.0.so.0',
]:
    try:
        ctypes.CDLL(f'/app/wheels/{lib}')
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

ADAPTER_PATH    = '/org/bluez/hci0'
LAUNCHER_SOCK   = '/app/launcher.sock'
MAX_HISTORY     = 20
TRUSTED_FILE    = '/app/trusted_devices.json'
SCHEDULE_FILE   = '/app/schedule.json'
WATCHLATER_FILE = '/app/watchlater.json'

BT_CMD_FILE    = '/app/bt_cmd.txt'
BT_RESULT_FILE = '/app/bt_result.txt'

PHONE_SVC_UUID = 'a00b0000-0000-0000-0000-000000000000'
PHONE_CMD_UUID = 'a00b0002-0000-0000-0000-000000000000'
PHONE_EVT_UUID = 'a00b0003-0000-0000-0000-000000000000'

ui               = WebUI()
led_state        = False
current_url      = None
current_mode     = 'idle'
url_history      = []
now_playing_title = ''

queue        = []
queue_index  = -1
queue_active = False
queue_paused = False

schedule         = []
schedule_playing = False
watch_later      = []

bus             = None
is_scanning     = False
scan_results    = {}
connected       = {}
trusted         = {}
discovering     = set()

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
        msg   = json.dumps({'event': event, **payload})
        data  = msg.encode('utf-8')
        size  = 18
        chunks = [data[i:i+size] for i in range(0, len(data), size)]
        total  = len(chunks)
        for idx, chunk in enumerate(chunks):
            packet = bytes([idx, total]) + chunk
            evt_char_global.update_value(list(packet))

def extract_video_id(url: str):
    for p in [r'(?:v=)([A-Za-z0-9_-]{11})', r'(?:youtu\.be/)([A-Za-z0-9_-]{11})',
              r'(?:embed/)([A-Za-z0-9_-]{11})', r'(?:shorts/)([A-Za-z0-9_-]{11})']:
        m = re.search(p, url)
        if m: return m.group(1)
    return None

def is_youtube_url(url: str) -> bool:
    return 'youtube.com' in url or 'youtu.be' in url


def load_trusted():
    global trusted
    try:
        if os.path.exists(TRUSTED_FILE):
            with open(TRUSTED_FILE, 'r') as f:
                trusted = json.load(f)
    except Exception as e:
        log(f'[TRUST] Load failed: {e}')

def save_trusted():
    try:
        with open(TRUSTED_FILE, 'w') as f:
            json.dump(trusted, f)
    except Exception: pass

def push_trusted():
    devices = [{'mac': mac, 'name': name} for mac, name in trusted.items()]
    push_to_phone('trusted_devices', {'devices': devices})


def load_schedule():
    global schedule
    try:
        if os.path.exists(SCHEDULE_FILE):
            with open(SCHEDULE_FILE, 'r') as f:
                schedule = json.load(f)
            log(f'[SCHEDULE] Loaded {len(schedule)} entries')
    except Exception as e:
        log(f'[SCHEDULE] Load failed: {e}')

def save_schedule():
    try:
        with open(SCHEDULE_FILE, 'w') as f:
            json.dump(schedule, f)
    except Exception: pass

def push_schedule():
    push_to_phone('schedule_update', {'entries': schedule})

def get_todays_entry():
    today = datetime.date.today().isoformat()
    for entry in schedule:
        if entry.get('date') == today:
            return entry
    return None

def is_in_schedule_window() -> bool:
    return get_todays_entry() is not None

def get_next_entry() -> dict:
    today = datetime.date.today()
    future = []
    for entry in schedule:
        try:
            d = datetime.date.fromisoformat(entry['date'])
            if d >= today:
                future.append(entry)
        except Exception:
            pass
    future.sort(key=lambda e: e['date'])
    return future[0] if future else {}

def schedule_tick():
    global schedule_playing
    in_window = is_in_schedule_window()
    entry     = get_todays_entry()
    if in_window and not schedule_playing and entry and not queue_active:
        playlist = entry.get('playlist', [])
        if playlist:
            log(f'[SCHEDULE] Today has {len(playlist)} videos')
            schedule_playing = True
            GLib.idle_add(queue_set, list(playlist))
            GLib.idle_add(queue_play)
    elif not in_window and schedule_playing:
        schedule_playing = False
    next_e = get_next_entry()
    push_to_phone('schedule_tick', {
        'in_window':   in_window,
        'next_window': next_e,
        'time':        now_str(),
    })


def load_watch_later():
    global watch_later
    try:
        if os.path.exists(WATCHLATER_FILE):
            with open(WATCHLATER_FILE, 'r') as f:
                watch_later = json.load(f)
            log(f'[WL] Loaded {len(watch_later)} items')
    except Exception as e:
        log(f'[WL] Load failed: {e}')

def save_watch_later():
    try:
        with open(WATCHLATER_FILE, 'w') as f:
            json.dump(watch_later, f)
    except Exception: pass

def push_watch_later():
    push_to_phone('watchlater_update', {'items': watch_later})


def launcher_send(cmd: str) -> str:
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect(LAUNCHER_SOCK)
        s.sendall((cmd + '\n').encode('utf-8'))
        chunks = []
        while True:
            chunk = s.recv(4096)
            if not chunk: break
            chunks.append(chunk)
        s.close()
        return b''.join(chunks).decode('utf-8').strip()
    except Exception as e:
        log(f'[LAUNCHER] Send failed ({cmd}): {e}')
        return 'error'

def launcher_ping() -> bool:
    return launcher_send('ping') == 'pong'


def push_queue_status():
    status = {
        'active':  queue_active, 'paused': queue_paused,
        'index':   queue_index,  'total':  len(queue),
        'queue':   queue,
        'current': queue[queue_index] if 0 <= queue_index < len(queue) else None,
        'time':    now_str(),
    }
    ui.send_message('queue_status', status)
    push_to_phone('queue_status', status)


def set_mode(mode: str):
    global current_mode
    current_mode = mode
    log(f'[MODE] {mode}')
    ui.send_message('mode_update', {'mode': mode, 'time': now_str()})
    ui.send_message('display_cmd', {'cmd': 'set_mode', 'mode': mode})
    launcher_send(f'mode:{mode}')
    push_to_phone('mode_update', {'mode': mode, 'time': now_str()})

def handle_url(url: str, title: str = ''):
    global current_url
    url = url.strip().replace('\x00','').replace('\r','').replace('\n','')
    url = ''.join(c for c in url if 32 <= ord(c) < 127).strip()
    if not url: return
    if not is_youtube_url(url):
        push_to_phone('url_rejected', {'url': url, 'reason': 'Not a YouTube link', 'time': now_str()})
        return
    video_id = extract_video_id(url)
    if not video_id:
        push_to_phone('url_rejected', {'url': url, 'reason': 'Could not extract video ID', 'time': now_str()})
        return
    log(f'[URL] {url} (ID: {video_id})')
    current_url = url
    url_history.insert(0, {'url': url, 'video_id': video_id, 'title': title, 'time': now_str()})
    if len(url_history) > MAX_HISTORY: url_history.pop()
    push_to_phone('url_update', {'url': url, 'video_id': video_id, 'title': title, 'time': now_str()})
    push_to_phone('url_history', {'history': url_history})
    threading.Thread(target=_play, args=(video_id, title), daemon=True).start()

def _play(video_id: str, title: str = ''):
    global now_playing_title
    now_playing_title = title
    launcher_send(f'play:{video_id}')
    time.sleep(1)
    set_mode('youtube')
    ui.send_message('display_cmd', {'cmd': 'play', 'video_id': video_id})
    log(f'[PLAYER] Play: {video_id} "{title}"')

def handle_player_cmd(cmd: str):
    log(f'[PLAYER] {cmd}')
    if cmd == 'stop':
        ui.send_message('display_cmd', {'cmd': 'stop'})
        global current_mode, queue_active, queue_paused, now_playing_title
        current_mode = 'idle'; queue_active = False; queue_paused = False
        now_playing_title = ''
        push_to_phone('mode_update', {'mode': 'idle', 'time': now_str()})
        push_to_phone('now_playing', {'video_id': '', 'title': ''})
    elif cmd in ('clock', 'idle', 'youtube'):
        set_mode(cmd)
    else:
        ui.send_message('display_cmd', {'cmd': cmd})
    push_to_phone('player_state', {'cmd': cmd, 'time': now_str()})


def queue_set(items: list):
    global queue, queue_index, queue_active, queue_paused
    queue = items; queue_index = -1; queue_active = False; queue_paused = False
    push_queue_status()

def queue_play():
    global queue_index, queue_active, queue_paused
    if not queue: return
    queue_index = 0; queue_active = True; queue_paused = False
    push_queue_status()
    _queue_play_current()

def queue_pause():
    global queue_paused
    if not queue_active: return
    queue_paused = True
    ui.send_message('display_cmd', {'cmd': 'pause'})
    push_queue_status()

def queue_resume():
    global queue_paused
    if not queue_active: return
    queue_paused = False
    ui.send_message('display_cmd', {'cmd': 'resume'})
    push_queue_status()

def queue_skip():
    global queue_index, queue_active, schedule_playing
    if not queue_active: return
    if schedule_playing and not is_in_schedule_window():
        schedule_playing = False; queue_active = False; queue_index = -1
        set_mode('clock'); push_queue_status(); return
    queue_index += 1
    if queue_index >= len(queue):
        queue_active = False; queue_index = -1
        if schedule_playing: schedule_playing = False
        set_mode('idle'); push_queue_status()
        push_to_phone('now_playing', {'video_id': '', 'title': ''})
        return
    push_queue_status()
    _queue_play_current()

def queue_replay():
    if queue_active and queue_index >= 0:
        _queue_play_current()

def queue_goto(index: int):
    global queue_index, queue_active, queue_paused
    if 0 <= index < len(queue):
        queue_index = index; queue_active = True; queue_paused = False
        push_queue_status(); _queue_play_current()

def queue_stop():
    global queue_active, queue_paused, queue_index, schedule_playing
    queue_active = False; queue_paused = False
    queue_index = -1; schedule_playing = False
    ui.send_message('display_cmd', {'cmd': 'stop'})
    set_mode('idle'); push_queue_status()
    push_to_phone('now_playing', {'video_id': '', 'title': ''})

def _queue_play_current():
    if 0 <= queue_index < len(queue):
        item  = queue[queue_index]
        vid   = item.get('video_id', '')
        title = item.get('title', '')
        log(f'[QUEUE] [{queue_index+1}/{len(queue)}] {title or vid}')
        threading.Thread(target=_play, args=(vid, title), daemon=True).start()

def on_video_ended():
    if queue_active and not queue_paused:
        GLib.idle_add(queue_skip)


def _bt_write_cmd(cmd: str):
    try:
        with open(BT_CMD_FILE, 'w') as f:
            f.write(cmd)
    except Exception as e:
        log(f'[BT] Write cmd failed: {e}')

def _bt_wait_result(keyword: str, timeout: int = 20) -> str:
    start = time.time()
    while time.time() - start < timeout:
        try:
            with open(BT_RESULT_FILE, 'r') as f:
                content = f.read()
            if keyword in content:
                return content
        except Exception: pass
        time.sleep(0.5)
    return ''

def _bt_connect(mac: str):
    log(f'[BT] Connecting {mac}...')
    _bt_write_cmd(f'BT_CONNECT:{mac}')
    result = _bt_wait_result(f'connected:{mac}', timeout=25)
    if result:
        name = mac
        try:
            for line in result.split('\n'):
                if f'connected:{mac}|' in line:
                    parts = line.strip().split(f'connected:{mac}|', 1)
                    if len(parts) == 2 and parts[1].strip():
                        name = parts[1].strip()
                        break
        except Exception: pass
        push_to_phone('bt_audio_connected', {'mac': mac, 'name': name, 'time': now_str()})
        log(f'[BT] Connected: {mac} ({name})')
        # Resend current video so PipeWire routes new audio stream to BT sink
        if current_url:
            video_id = extract_video_id(current_url)
            if video_id:
                time.sleep(2)
                log(f'[BT] Resuming video on BT sink: {video_id}')
                GLib.idle_add(set_mode, 'youtube')
                ui.send_message('display_cmd', {'cmd': 'play', 'video_id': video_id})
    else:
        push_to_phone('bt_audio_error', {'mac': mac, 'time': now_str()})
        log(f'[BT] Connect failed: {mac}')

def _bt_disconnect(mac: str):
    log(f'[BT] Disconnecting {mac}...')
    _bt_write_cmd(f'BT_DISCONNECT:{mac}')
    _bt_wait_result(f'disconnected:{mac}', timeout=10)
    push_to_phone('bt_audio_disconnected', {'mac': mac, 'time': now_str()})

def _bt_pair(mac: str):
    log(f'[BT] Pairing {mac}...')
    _bt_write_cmd(f'BT_PAIR:{mac}')
    _bt_wait_result(f'paired:{mac}', timeout=30)
    push_to_phone('bt_paired', {'mac': mac, 'time': now_str()})
    log(f'[BT] Paired: {mac}')

def _bt_forget(mac: str):
    log(f'[BT] Forgetting {mac}...')
    _bt_write_cmd(f'BT_FORGET:{mac}')
    _bt_wait_result(f'forgotten:{mac}', timeout=10)
    push_to_phone('bt_forgotten', {'mac': mac, 'time': now_str()})

def handle_phone_command(text: str):
    global led_state, schedule
    text = text.strip()
    log(f'[PHONE] {text[:80]}')

    if text.startswith('YT:'):
        parts = text[3:].strip().split('||', 1)
        url   = parts[0].strip()
        title = parts[1].strip() if len(parts) > 1 else ''
        GLib.idle_add(handle_url, url, title)

    elif text.startswith('QUEUE:'):
        try:
            GLib.idle_add(queue_set, json.loads(text[6:]))
        except Exception as e:
            log(f'[QUEUE] Parse failed: {e}')

    elif text.startswith('SCHEDULE:'):
        try:
            schedule = json.loads(text[9:])
            save_schedule()
            push_schedule()
            log(f'[SCHEDULE] Updated - {len(schedule)} entries')
        except Exception as e:
            log(f'[SCHEDULE] Parse failed: {e}')

    elif text.startswith('WATCHLATER_ADD:'):
        try:
            parts    = text[15:].strip().split('||', 2)
            url      = parts[0].strip()
            title    = parts[1].strip() if len(parts) > 1 else ''
            video_id = parts[2].strip() if len(parts) > 2 else ''
            watch_later.insert(0, {
                'url':      url,
                'title':    title,
                'video_id': video_id,
                'added_at': now_str(),
            })
            save_watch_later()
            push_watch_later()
            log(f'[WL] Added: {title or url}')
        except Exception as e:
            log(f'[WL] Add failed: {e}')

    elif text.startswith('WATCHLATER_REMOVE:'):
        url = text[18:].strip()
        watch_later[:] = [i for i in watch_later if i.get('url') != url]
        save_watch_later()
        push_watch_later()
        log(f'[WL] Removed: {url}')

    elif text.startswith('CMD:'):
        cmd = text[4:].strip()
        if cmd == 'LED_ON':
            led_state = True; Bridge.call("set_led_state", True)
            push_to_phone('led_status', {'state': True, 'time': now_str()})
        elif cmd == 'LED_OFF':
            led_state = False; Bridge.call("set_led_state", False)
            push_to_phone('led_status', {'state': False, 'time': now_str()})
        elif cmd == 'LED_TOGGLE':
            led_state = not led_state; Bridge.call("set_led_state", led_state)
            push_to_phone('led_status', {'state': led_state, 'time': now_str()})
        elif cmd == 'MODE_IDLE':    GLib.idle_add(set_mode, 'idle')
        elif cmd == 'MODE_YOUTUBE': GLib.idle_add(set_mode, 'youtube')
        elif cmd == 'MODE_CLOCK':   GLib.idle_add(set_mode, 'clock')
        elif cmd == 'PLAYER_PAUSE':    GLib.idle_add(handle_player_cmd, 'pause')
        elif cmd == 'PLAYER_RESUME':   GLib.idle_add(handle_player_cmd, 'resume')
        elif cmd == 'PLAYER_STOP':     GLib.idle_add(handle_player_cmd, 'stop')
        elif cmd == 'PLAYER_MUTE':     GLib.idle_add(handle_player_cmd, 'mute')
        elif cmd == 'PLAYER_UNMUTE':   GLib.idle_add(handle_player_cmd, 'unmute')
        elif cmd == 'PLAYER_VOL_UP':   GLib.idle_add(handle_player_cmd, 'vol_up')
        elif cmd == 'PLAYER_VOL_DOWN': GLib.idle_add(handle_player_cmd, 'vol_down')
        elif cmd == 'PLAYER_SEEK_FWD': GLib.idle_add(handle_player_cmd, 'seek_fwd')
        elif cmd == 'PLAYER_SEEK_BACK':GLib.idle_add(handle_player_cmd, 'seek_back')
        elif cmd == 'PLAYER_REPLAY':   GLib.idle_add(handle_player_cmd, 'replay')
        elif cmd.startswith('PLAYER_QUALITY:'):
            quality = cmd.split(':')[1].strip()
            GLib.idle_add(handle_player_cmd, f'quality:{quality}')
        elif cmd == 'QUEUE_PLAY':   GLib.idle_add(queue_play)
        elif cmd == 'QUEUE_PAUSE':  GLib.idle_add(queue_pause)
        elif cmd == 'QUEUE_RESUME': GLib.idle_add(queue_resume)
        elif cmd == 'QUEUE_SKIP':   GLib.idle_add(queue_skip)
        elif cmd == 'QUEUE_REPLAY': GLib.idle_add(queue_replay)
        elif cmd == 'QUEUE_STOP':   GLib.idle_add(queue_stop)
        elif cmd.startswith('QUEUE_GOTO:'):
            try: GLib.idle_add(queue_goto, int(cmd.split(':')[1]))
            except Exception: pass
        elif cmd == 'SCHEDULE_GET':   push_schedule()
        elif cmd == 'WATCHLATER_GET': push_watch_later()
        elif cmd == 'SCAN_START':   GLib.idle_add(start_scan)
        elif cmd == 'SCAN_STOP':    GLib.idle_add(stop_scan)
        elif cmd.startswith('CONNECT:'):
            mac = cmd[8:].strip()
            if mac: connect_device(mac)
        elif cmd.startswith('DISCONNECT:'):
            mac = cmd[11:].strip()
            if mac: disconnect_device(mac)
        elif cmd.startswith('FORGET:'):
            mac = cmd[7:].strip()
            if mac: GLib.idle_add(forget_device, mac)
        elif cmd == 'GET_STATUS': _push_full_status_to_phone()
        elif cmd.startswith('BT_CONNECT:'):
            mac = cmd[11:].strip()
            threading.Thread(target=_bt_connect, args=(mac,), daemon=True).start()
        elif cmd.startswith('BT_DISCONNECT:'):
            mac = cmd[14:].strip()
            threading.Thread(target=_bt_disconnect, args=(mac,), daemon=True).start()
        elif cmd.startswith('BT_PAIR:'):
            mac = cmd[8:].strip()
            threading.Thread(target=_bt_pair, args=(mac,), daemon=True).start()
        elif cmd.startswith('BT_FORGET:'):
            mac = cmd[10:].strip()
            threading.Thread(target=_bt_forget, args=(mac,), daemon=True).start()
        elif cmd == 'BT_STATUS':
            result = launcher_send('BT_STATUS')
            push_to_phone('bt_status', {'result': result, 'time': now_str()})
        elif cmd == 'BT_GET_CONNECTED':
            bt_mac, bt_name = _get_bt_connected()
            if bt_mac:
                push_to_phone('bt_audio_connected',
                    {'mac': bt_mac, 'name': bt_name, 'time': now_str()})
            else:
                push_to_phone('bt_audio_disconnected', {'time': now_str()})
        elif cmd == 'BT_LIST':
            raw = launcher_send('BT_LIST')
            devices = []
            for line in raw.strip().split('\n'):
                if line.startswith('Device '):
                    parts = line.split(' ', 2)
                    if len(parts) >= 3:
                        mac  = parts[1].strip()
                        name = parts[2].strip()
                        if name and name != mac:
                            devices.append({'mac': mac, 'name': name})
            push_to_phone('bt_paired_devices', {'devices': devices, 'time': now_str()})
        else: log(f'[CMD] Unknown: {cmd}')

def _get_bt_connected():
    try:
        if os.path.exists('/app/bt_connected.txt'):
            with open('/app/bt_connected.txt', 'r') as f:
                entry = f.read().strip()
            if '|' in entry:
                mac, name = entry.split('|', 1)
                return mac.strip(), name.strip()
            elif entry:
                return entry.strip(), entry.strip()
    except Exception: pass
    return None, None

def _push_full_status_to_phone():
    push_to_phone('mode_update',  {'mode': current_mode, 'time': now_str()})
    push_to_phone('led_status',   {'state': led_state, 'time': now_str()})
    push_to_phone('url_history',  {'history': url_history})
    push_to_phone('now_playing',  {'video_id': '', 'title': now_playing_title})
    push_to_phone('queue_status', {
        'active': queue_active, 'paused': queue_paused,
        'index': queue_index, 'total': len(queue), 'queue': queue,
        'current': queue[queue_index] if 0 <= queue_index < len(queue) else None,
    })
    push_to_phone('schedule_update', {'entries': schedule})
    push_to_phone('watchlater_update', {'items': watch_later})
    push_to_phone('scan_results', {'devices': [
        {'mac': mac, 'name': d.get('name',''), 'rssi': d.get('rssi',0)}
        for mac, d in scan_results.items()]})
    push_to_phone('trusted_devices', {'devices': [
        {'mac': mac, 'name': name} for mac, name in trusted.items()]})
    bt_mac, bt_name = _get_bt_connected()
    if bt_mac:
        def _push_bt():
            push_to_phone('bt_audio_connected', {'mac': bt_mac, 'name': bt_name, 'time': now_str()})
        GLib.timeout_add(1500, lambda: (_push_bt(), False)[1])


def push_scan_results():
    devices = [{'mac': mac, 'name': d.get('name',''), 'rssi': d.get('rssi',0)}
               for mac, d in scan_results.items()]
    ui.send_message('scan_results', {'devices': devices})
    push_to_phone('scan_results', {'devices': devices})

def push_connected_devices():
    devices = [{'mac': mac, 'name': d.get('name', mac), 'characteristics': [
        {'uuid': uuid, 'name': c.get('name', uuid[:8]),
         'value': c.get('value',''), 'flags': c.get('flags',[])}
        for uuid, c in d.get('characteristics', {}).items()]}
        for mac, d in connected.items()]
    ui.send_message('connected_devices', {'devices': devices})
    push_to_phone('connected_devices', {'devices': devices})

def get_all_objects():
    try:
        mgr = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, '/'), DBUS_OM_IFACE)
        return mgr.GetManagedObjects()
    except Exception: return {}

def start_scan():
    global is_scanning
    if is_scanning:
        try:
            dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, ADAPTER_PATH),
                ADAPTER_IFACE).StopDiscovery()
        except Exception: pass
        is_scanning = False; time.sleep(0.5)
    try:
        adapter_if = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, ADAPTER_PATH), ADAPTER_IFACE)
        adapter_if.SetDiscoveryFilter(dbus.Dictionary({'Transport': dbus.String('le')}, signature='sv'))
        adapter_if.StartDiscovery()
        is_scanning = True
        push_to_phone('scan_status', {'scanning': True, 'time': now_str()})
        threading.Timer(12.0, lambda: GLib.idle_add(stop_scan)).start()
    except Exception as e:
        log(f'[SCAN] Start failed: {e}')

def stop_scan():
    global is_scanning
    if not is_scanning: return
    try:
        dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, ADAPTER_PATH),
            ADAPTER_IFACE).StopDiscovery()
        is_scanning = False
        push_to_phone('scan_status', {'scanning': False, 'time': now_str()})
    except Exception as e:
        log(f'[SCAN] Stop failed: {e}')

def connect_device(mac: str):
    threading.Thread(target=_connect_device, args=(mac,), daemon=True).start()

def _connect_device(mac: str):
    dev_path = scan_results.get(mac, {}).get('path')
    if not dev_path:
        for path, ifaces in get_all_objects().items():
            if DEVICE_IFACE in ifaces:
                if str(ifaces[DEVICE_IFACE].get('Address','')).upper() == mac.upper():
                    dev_path = path; break
    if not dev_path: return
    try:
        dev_obj = bus.get_object(BLUEZ_SERVICE_NAME, dev_path)
        dev_if  = dbus.Interface(dev_obj, DEVICE_IFACE)
        props   = dbus.Interface(dev_obj, DBUS_PROP_IFACE)
        if not bool(props.Get(DEVICE_IFACE, 'Connected')):
            dev_if.Connect()
        name = mac
        try: name = str(props.Get(DEVICE_IFACE, 'Name'))
        except Exception: pass
        connected[mac] = {'name': name, 'path': dev_path, 'characteristics': {}}
        push_to_phone('device_connected', {'mac': mac, 'name': name, 'time': now_str()})
        push_connected_devices()
        threading.Thread(target=_discover_characteristics,
            args=(mac, dev_path), daemon=True).start()
    except Exception as e:
        log(f'[CONNECT] Failed {mac}: {e}')
        push_to_phone('device_error', {'mac': mac, 'error': str(e), 'time': now_str()})

def _discover_characteristics(mac, dev_path):
    if mac in discovering: return
    discovering.add(mac); time.sleep(2)
    for path, ifaces in get_all_objects().items():
        if GATT_CHRC_IFACE not in ifaces or not path.startswith(dev_path): continue
        props = ifaces[GATT_CHRC_IFACE]
        uuid  = str(props.get('UUID',''))
        flags = [str(f) for f in props.get('Flags',[])]
        connected[mac]['characteristics'][uuid] = {
            'uuid': uuid, 'name': _known_uuid_name(uuid),
            'flags': flags, 'value': '', 'path': path}
        if 'read' in flags:
            try:
                raw = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, path),
                    GATT_CHRC_IFACE).ReadValue(dbus.Dictionary({}, signature='sv'))
                connected[mac]['characteristics'][uuid]['value'] = \
                    _decode_value(uuid, bytes(raw))
            except Exception: pass
        if 'notify' in flags or 'indicate' in flags:
            try:
                dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, path),
                    GATT_CHRC_IFACE).StartNotify()
                bus.add_signal_receiver(
                    lambda iface, changed, inv, p=path, m=mac, u=uuid:
                        _on_char_changed(m, u, iface, changed),
                    dbus_interface=DBUS_PROP_IFACE,
                    signal_name='PropertiesChanged', path=path)
            except Exception: pass
    discovering.discard(mac); push_connected_devices()

def _on_char_changed(mac, uuid, interface, changed):
    if interface != GATT_CHRC_IFACE or 'Value' not in changed: return
    try:
        value = _decode_value(uuid, bytes(changed['Value']))
        if mac in connected and uuid in connected[mac]['characteristics']:
            connected[mac]['characteristics'][uuid]['value'] = value
        push_to_phone('characteristic_update',
            {'mac': mac, 'uuid': uuid, 'name': _known_uuid_name(uuid),
             'value': value, 'time': now_str()})
        push_connected_devices()
    except Exception: pass

def disconnect_device(mac):
    threading.Thread(target=_disconnect_device, args=(mac,), daemon=True).start()

def _disconnect_device(mac):
    dev = connected.get(mac)
    if not dev: return
    try:
        dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, dev['path']),
            DEVICE_IFACE).Disconnect()
    except Exception: pass
    connected.pop(mac, None)
    push_to_phone('device_disconnected', {'mac': mac, 'time': now_str()})
    push_connected_devices()

def forget_device(mac):
    trusted.pop(mac, None); save_trusted(); push_trusted()

def _known_uuid_name(uuid):
    known = {'00002a19':'Battery Level','00002a6e':'Temperature',
             '00002a37':'Heart Rate','00002a29':'Manufacturer',
             '00002a24':'Model Number','00002a25':'Serial Number',
             '00002a27':'Hardware Rev','00002a26':'Firmware Rev',
             '00002a6f':'Humidity','00002a6d':'Pressure',
             '00002a00':'Device Name','00002a01':'Appearance'}
    return known.get(uuid[:8].lower(), uuid[:8])

def _decode_value(uuid, raw):
    if not raw: return ''
    prefix = uuid[:8].lower()
    try:
        if prefix == '00002a19': return f'{raw[0]}%'
        if prefix == '00002a6e':
            return f'{int.from_bytes(raw[:2],"little",signed=True)/100:.1f} C'
        if prefix == '00002a37': return f'{raw[1]} bpm'
        if prefix in ('00002a29','00002a24','00002a25','00002a27',
                      '00002a26','00002a00'):
            return raw.decode('utf-8', errors='ignore').strip()
        try: return raw.decode('utf-8').strip()
        except Exception: return raw.hex()
    except Exception: return raw.hex()


class BLEObjectWatcher:
    def __init__(self, bus):
        bus.add_signal_receiver(self._interfaces_added,
            dbus_interface=DBUS_OM_IFACE, signal_name='InterfacesAdded')
        bus.add_signal_receiver(self._interfaces_removed,
            dbus_interface=DBUS_OM_IFACE, signal_name='InterfacesRemoved')
        bus.add_signal_receiver(self._props_changed,
            dbus_interface=DBUS_PROP_IFACE, signal_name='PropertiesChanged',
            arg0=DEVICE_IFACE, path_keyword='path')

    def _interfaces_added(self, path, interfaces):
        if DEVICE_IFACE not in interfaces: return
        props = interfaces[DEVICE_IFACE]
        mac = str(props.get('Address','')); name = str(props.get('Name', mac))
        rssi = int(props.get('RSSI', 0))
        if not mac: return
        scan_results[mac] = {'name': name, 'rssi': rssi, 'path': path}
        push_scan_results()
        if mac in trusted and mac not in connected:
            threading.Timer(1.0, lambda m=mac: connect_device(m)).start()

    def _interfaces_removed(self, path, interfaces):
        if DEVICE_IFACE not in interfaces: return
        for mac, d in list(scan_results.items()):
            if d.get('path') == path: scan_results.pop(mac, None)
        push_scan_results()

    def _props_changed(self, interface, changed, invalidated, path):
        if interface != DEVICE_IFACE: return
        for mac, d in scan_results.items():
            if d.get('path') == path:
                if 'RSSI' in changed: scan_results[mac]['rssi'] = int(changed['RSSI'])
                if 'Name' in changed: scan_results[mac]['name'] = str(changed['Name'])
        push_scan_results()
        if 'Connected' in changed:
            for mac, d in list(connected.items()):
                if d.get('path') == path and not bool(changed['Connected']):
                    connected.pop(mac, None)
                    push_to_phone('device_disconnected',
                        {'mac': mac, 'time': now_str()})
                    push_connected_devices()

def _autoconnect_existing():
    if not trusted: return
    try:
        for path, ifaces in get_all_objects().items():
            if DEVICE_IFACE not in ifaces: continue
            mac = str(ifaces[DEVICE_IFACE].get('Address',''))
            if mac and mac in trusted and mac not in connected:
                connect_device(mac)
    except Exception as e:
        log(f'[AUTO] Failed: {e}')


class PhoneAdvertisement(dbus.service.Object):
    def __init__(self, bus, index):
        self.path = f'/org/bluez/hci0/advertisement{index}'
        self.bus  = bus
        dbus.service.Object.__init__(self, bus, self.path)

    @dbus.service.method(DBUS_PROP_IFACE, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        if interface != LE_ADVERTISEMENT_IFACE:
            raise dbus.exceptions.DBusException('org.bluez.Error.InvalidArgs')
        return {'Type': dbus.String('peripheral'),
                'ServiceUUIDs': dbus.Array([PHONE_SVC_UUID], signature='s'),
                'LocalName': dbus.String('BLE-Hub'),
                'IncludeTxPower': dbus.Boolean(True),
                'Discoverable': dbus.Boolean(True)}

    @dbus.service.method(LE_ADVERTISEMENT_IFACE)
    def Release(self): pass


class PhoneApplication(dbus.service.Object):
    def __init__(self, bus):
        self.path = '/org/bluez/hci0/phoneapp'; self.services = []
        dbus.service.Object.__init__(self, bus, self.path)

    def add_service(self, svc): self.services.append(svc)

    @dbus.service.method(DBUS_OM_IFACE, out_signature='a{oa{sa{sv}}}')
    def GetManagedObjects(self):
        resp = {}
        for svc in self.services:
            resp[svc.path] = {GATT_SERVICE_IFACE: {
                'UUID': dbus.String(svc.uuid), 'Primary': dbus.Boolean(True)}}
            for c in svc.chars: resp[c.path] = {GATT_CHRC_IFACE: c.get_props()}
        return resp


class PhoneService(dbus.service.Object):
    def __init__(self, bus):
        self.path = '/org/bluez/hci0/phoneapp/service0'
        self.uuid = PHONE_SVC_UUID; self.chars = []
        dbus.service.Object.__init__(self, bus, self.path)


class PhoneCmdChar(dbus.service.Object):
    def __init__(self, bus, service):
        self.path = '/org/bluez/hci0/phoneapp/service0/char0'
        self.uuid = PHONE_CMD_UUID; self.service = service
        self.value = dbus.Array([], signature='y')
        dbus.service.Object.__init__(self, bus, self.path)

    def get_props(self):
        return {'Service': dbus.ObjectPath(self.service.path),
                'UUID': dbus.String(self.uuid),
                'Flags': dbus.Array(['write','write-without-response'],
                    signature='s')}

    @dbus.service.method(GATT_CHRC_IFACE, in_signature='aya{sv}')
    def WriteValue(self, value, options):
        self.value = value
        handle_phone_command(bytes(value).decode('utf-8', errors='ignore'))


class PhoneEvtChar(dbus.service.Object):
    def __init__(self, bus, service):
        self.path = '/org/bluez/hci0/phoneapp/service0/char1'
        self.uuid = PHONE_EVT_UUID; self.service = service
        self.value = dbus.Array([], signature='y'); self.notifying = False
        dbus.service.Object.__init__(self, bus, self.path)

    def get_props(self):
        return {'Service': dbus.ObjectPath(self.service.path),
                'UUID': dbus.String(self.uuid),
                'Flags': dbus.Array(['notify'], signature='s'),
                'Notifying': dbus.Boolean(self.notifying)}

    @dbus.service.method(GATT_CHRC_IFACE)
    def StartNotify(self):
        if self.notifying: return
        self.notifying = True
        GLib.idle_add(_push_full_status_to_phone)

    @dbus.service.method(GATT_CHRC_IFACE)
    def StopNotify(self): self.notifying = False

    @dbus.service.signal(DBUS_PROP_IFACE, signature='sa{sv}as')
    def PropertiesChanged(self, interface, changed, invalidated): pass

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
        print(f'[BLE] SystemBus failed: {e}'); return

    BLEObjectWatcher(bus)
    load_trusted(); load_schedule(); load_watch_later()
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
        gatt_mgr_global.RegisterApplication(dbus.ObjectPath(phone_app.path), {},
            reply_handler=lambda: log('[PHONE] GATT app registered'),
            error_handler=lambda e: log(f'[PHONE] GATT failed: {e}'))
        adv_global = PhoneAdvertisement(bus, 0)
        adv_mgr_global.RegisterAdvertisement(dbus.ObjectPath(adv_global.path), {},
            reply_handler=lambda: log('[PHONE] Advertising as BLE-Hub'),
            error_handler=lambda e: log(f'[PHONE] Adv failed: {e}'))
    except Exception as e:
        log(f'[PHONE] Setup failed: {e}')

    log('=' * 50)
    log(' BLE Hub Started')
    log('=' * 50)
    GLib.MainLoop().run()


def on_send_url(client, data):
    url   = (data or {}).get('url', '')
    title = (data or {}).get('title', '')
    GLib.idle_add(handle_url, url, title)

def on_player_cmd(client, data):
    GLib.idle_add(handle_player_cmd, (data or {}).get('cmd',''))

def on_set_mode(client, data):
    GLib.idle_add(set_mode, (data or {}).get('mode','idle'))

def on_scan_start(client, data):   GLib.idle_add(start_scan)
def on_scan_stop(client, data):    GLib.idle_add(stop_scan)

def on_connect_device(client, data):
    mac = (data or {}).get('mac','')
    if mac: connect_device(mac)

def on_disconnect_device(client, data):
    mac = (data or {}).get('mac','')
    if mac: disconnect_device(mac)

def on_forget_device(client, data):
    mac = (data or {}).get('mac','')
    if mac: GLib.idle_add(forget_device, mac)

def on_toggle_led(client, data):
    global led_state
    led_state = not led_state; Bridge.call("set_led_state", led_state)
    push_to_phone('led_status', {'state': led_state, 'time': now_str()})

def on_player_event(client, data):
    state = (data or {}).get('state', '')
    if state == 'ended': GLib.idle_add(on_video_ended)

def on_get_initial_state(client, data):
    ui.send_message('initial_state', {
        'mode': current_mode, 'current_url': current_url,
        'history': url_history, 'scanning': is_scanning,
        'queue_status': {
            'active': queue_active, 'paused': queue_paused,
            'index': queue_index, 'total': len(queue), 'queue': queue,
            'current': queue[queue_index] if 0 <= queue_index < len(queue) else None},
        'schedule': schedule,
        'watch_later': watch_later,
        'scan_results': [
            {'mac': mac, 'name': d.get('name',''), 'rssi': d.get('rssi',0)}
            for mac, d in scan_results.items()],
        'connected_devices': [
            {'mac': mac, 'name': d.get('name', mac), 'characteristics': [
                {'uuid': u, 'name': c.get('name', u[:8]),
                 'value': c.get('value',''), 'flags': c.get('flags',[])}
                for u, c in d.get('characteristics', {}).items()]}
            for mac, d in connected.items()],
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

def _schedule_loop():
    while True:
        time.sleep(60)
        GLib.idle_add(schedule_tick)

threading.Thread(target=_schedule_loop, daemon=True).start()
threading.Thread(target=ble_main, daemon=True).start()
App.run()
