# ble_gatt_serve.py — BLE Peripheral (GATT server) for youtube-display
# Board advertises, phone scans, connects, and writes URL + commands.
#
# Service UUID:   a01c0000-0000-0000-0000-000000000000
# CMD Char UUID:  a01c0001-0000-0000-0000-000000000000  (WRITE)
# EVT Char UUID:  a01c0002-0000-0000-0000-000000000000  (NOTIFY)
#
# Write protocol:
#   Raw YouTube URL         -> on_url()
#   CMD:PAUSE/RESUME/STOP/VOL_UP/VOL_DOWN -> on_cmd()
#   CMD:BT_SCAN_START       -> start BT scan via BlueZ D-Bus directly
#   CMD:BT_SCAN_STOP        -> stop BT scan via BlueZ D-Bus directly
#   CMD:BT_PAIR:<mac>       -> pair + trust via file bridge (host)
#   CMD:BT_CONNECT:<mac>    -> connect + set PipeWire sink via file bridge
#   CMD:BT_DISCONNECT:<mac> -> disconnect via file bridge
#   CMD:BT_FORGET:<mac>     -> unpair via file bridge
#   CMD:BT_LIST             -> push trusted devices via BlueZ D-Bus directly
#
# Notify protocol (EVT char) — JSON pushed to phone:
#   {"event":"bt_scan_results","devices":[{"mac":"..","name":"..","rssi":0}]}
#   {"event":"bt_scan_status","scanning":true/false}
#   {"event":"bt_trusted","devices":[{"mac":"..","name":"..","connected":bool}]}
#   {"event":"bt_connected","mac":"..","name":".."}
#   {"event":"bt_disconnected","mac":".."}
#   {"event":"bt_error","message":".."}

import os, sys, ctypes, threading, json, time

TYPELIBS_DIR = "/app/typelibs"
WHEELS_DIR   = "/app/wheels"
DBUS_SOCK    = "unix:path=/app/dbus.sock"

SHARED_LIBS = [
    "libm.so.6", "libcap.so.2", "libpcre2-8.so.0",
    "libselinux.so.1", "libaudit.so.1", "libcap-ng.so.0",
    "libexpat.so.1", "libdbus-1.so.3", "libapparmor.so.1",
    "libsystemd.so.0", "libgirepository-2.0.so.0",
]

def _load_libs():
    os.environ["GI_TYPELIB_PATH"] = TYPELIBS_DIR
    for lib in SHARED_LIBS:
        try:
            ctypes.CDLL(f"{WHEELS_DIR}/{lib}")
        except Exception as e:
            print(f"[BLE] lib {lib}: {e}", flush=True)
    sys.path.insert(0, "/usr/lib/python3/dist-packages")
    print("[BLE] Libraries loaded", flush=True)

_load_libs()

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

BLUEZ    = "org.bluez"
ADV_IF   = "org.bluez.LEAdvertisement1"
ADV_MGR  = "org.bluez.LEAdvertisingManager1"
PROP_IF  = "org.freedesktop.DBus.Properties"
GATT_MGR = "org.bluez.GattManager1"
GATT_SVC = "org.bluez.GattService1"
GATT_CHR = "org.bluez.GattCharacteristic1"
DBUS_OM  = "org.freedesktop.DBus.ObjectManager"
DEVICE_IF = "org.bluez.Device1"
ADAPTER_IF = "org.bluez.Adapter1"

SERVICE_UUID  = "a01c0000-0000-0000-0000-000000000000"
CMD_CHAR_UUID = "a01c0001-0000-0000-0000-000000000000"
EVT_CHAR_UUID = "a01c0002-0000-0000-0000-000000000000"
DEVICE_NAME   = "YT-Display"
ADAPTER_PATH  = "/org/bluez/hci0"

# Module-level bus — set once _run() connects, used by all BT functions
_bus = None
_evt_char_ref = None  # set once EvtCharacteristic is created

# File bridge paths (for host-side operations needing wpctl/bluetoothctl)
BT_CMD_FILE    = "/app/bt_cmd.txt"
BT_RESULT_FILE = "/app/bt_result.txt"
BT_TIMEOUT     = 15


# ── File bridge helpers ───────────────────────────────────────────────────────

def _bt_write(cmd: str):
    with open(BT_CMD_FILE, "w") as f:
        f.write(cmd)

def _bt_wait_result(timeout=BT_TIMEOUT) -> str:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(BT_RESULT_FILE):
            time.sleep(0.2)
            try:
                with open(BT_RESULT_FILE, "r") as f:
                    result = f.read().strip()
                os.remove(BT_RESULT_FILE)
                return result
            except Exception:
                pass
        time.sleep(0.3)
    return ""


# ── BlueZ D-Bus direct helpers ────────────────────────────────────────────────

def _get_all_devices():
    """Get all known BT devices from BlueZ via D-Bus. No bluetoothctl needed."""
    if not _bus:
        return {}
    try:
        mgr = dbus.Interface(
            _bus.get_object(BLUEZ, "/"),
            DBUS_OM
        )
        objects = mgr.GetManagedObjects()
        devices = {}
        for path, ifaces in objects.items():
            if DEVICE_IF not in ifaces:
                continue
            props = ifaces[DEVICE_IF]
            mac   = str(props.get("Address", ""))
            name  = str(props.get("Name", mac))
            trusted   = bool(props.get("Trusted", False))
            connected = bool(props.get("Connected", False))
            rssi      = int(props.get("RSSI", 0))
            if mac:
                devices[mac] = {
                    "mac": mac,
                    "name": name,
                    "trusted": trusted,
                    "connected": connected,
                    "rssi": rssi,
                    "path": str(path),
                }
        return devices
    except Exception as e:
        print(f"[BT] GetManagedObjects failed: {e}", flush=True)
        return {}

def _is_connected(mac: str) -> bool:
    devices = _get_all_devices()
    return devices.get(mac, {}).get("connected", False)


# ── BT functions — D-Bus direct (no bluetoothctl, no audio disruption) ───────

def bt_list_trusted():
    """Read trusted devices directly from BlueZ — zero audio disruption."""
    devices = _get_all_devices()
    trusted = [
        {
            "mac":       d["mac"],
            "name":      d["name"],
            "connected": d["connected"],
        }
        for d in devices.values()
        if d["trusted"]
    ]
    return {"event": "bt_trusted", "devices": trusted}


def bt_scan_start(on_result):
    """Start BT scan via BlueZ D-Bus directly — no bluetoothctl needed."""
    def _do_scan():
        if not _bus:
            GLib.idle_add(on_result, {"event": "bt_error", "message": "Bus not ready"})
            return
        try:
            adapter = dbus.Interface(
                _bus.get_object(BLUEZ, ADAPTER_PATH),
                ADAPTER_IF
            )
            # Set filter to LE only
            adapter.SetDiscoveryFilter(
                dbus.Dictionary({"Transport": dbus.String("le")}, signature="sv")
            )
            adapter.StartDiscovery()
            print("[BT] Scan started", flush=True)
            GLib.idle_add(on_result, {"event": "bt_scan_status", "scanning": True})

            # Push current known devices immediately
            _push_scan_snapshot(on_result)

            # Keep scanning for 12 seconds, push updates
            deadline = time.time() + 12
            seen = set()
            while time.time() < deadline:
                time.sleep(1)
                devices = _get_all_devices()
                changed = False
                for mac, d in devices.items():
                    if not d["trusted"] and mac not in seen and d["name"] != mac:
                        seen.add(mac)
                        changed = True
                if changed:
                    _push_scan_snapshot(on_result)

            try:
                adapter.StopDiscovery()
            except Exception:
                pass
            print("[BT] Scan stopped", flush=True)
            GLib.idle_add(on_result, {"event": "bt_scan_status", "scanning": False})
            # Push final snapshot
            _push_scan_snapshot(on_result)

        except Exception as e:
            print(f"[BT] Scan error: {e}", flush=True)
            GLib.idle_add(on_result, {"event": "bt_error", "message": str(e)})

    threading.Thread(target=_do_scan, daemon=True).start()
    return {"event": "bt_scan_status", "scanning": True}


def _push_scan_snapshot(on_result):
    """Push current scan results — all non-trusted devices with names."""
    devices = _get_all_devices()
    available = [
        {"mac": d["mac"], "name": d["name"], "rssi": d["rssi"]}
        for d in devices.values()
        if not d["trusted"] and d["name"] != d["mac"] and d["name"]
    ]
    if available:
        GLib.idle_add(on_result, {
            "event": "bt_scan_results",
            "devices": available
        })


def bt_scan_stop():
    """Stop BT scan via BlueZ D-Bus directly."""
    if not _bus:
        return {"event": "bt_scan_status", "scanning": False}
    try:
        adapter = dbus.Interface(
            _bus.get_object(BLUEZ, ADAPTER_PATH),
            ADAPTER_IF
        )
        adapter.StopDiscovery()
        print("[BT] Scan stopped by user", flush=True)
    except Exception as e:
        print(f"[BT] StopDiscovery: {e}", flush=True)
    return {"event": "bt_scan_status", "scanning": False}

# ── BT functions — file bridge (host-side, needs wpctl/bluetoothctl) ─────────

def bt_pair(mac):
    """Pair + trust device via host bluetoothctl."""
    def _do():
        _bt_write(f"BT_PAIR:{mac}")
        result = _bt_wait_result(25)
        devices = _get_all_devices()
        name = devices.get(mac, {}).get("name", mac)
        if "paired:" in result or "already paired" in result.lower():
            evt = {"event": "bt_connected", "mac": mac, "name": name}
        else:
            evt = {"event": "bt_error", "message": f"Pair failed: {result}"}
        if _evt_char_ref:
            GLib.idle_add(_evt_char_ref.push, evt)
            GLib.idle_add(_evt_char_ref.push, bt_list_trusted())
    threading.Thread(target=_do, daemon=True).start()


def bt_connect(mac):
    """Connect device + set as default PipeWire sink via host."""
    def _do():
        _bt_write(f"BT_CONNECT:{mac}")
        result = _bt_wait_result(20)
        devices = _get_all_devices()
        name = devices.get(mac, {}).get("name", mac)
        if "connected:" in result or "Connection successful" in result:
            evt = {"event": "bt_connected", "mac": mac, "name": name}
        else:
            evt = {"event": "bt_error", "message": f"Connect failed: {result}"}
        if _evt_char_ref:
            GLib.idle_add(_evt_char_ref.push, evt)
            GLib.idle_add(_evt_char_ref.push, bt_list_trusted())
    threading.Thread(target=_do, daemon=True).start()


def bt_disconnect(mac):
    """Disconnect device via host bluetoothctl."""
    def _do():
        _bt_write(f"BT_DISCONNECT:{mac}")
        _bt_wait_result(10)
        if _evt_char_ref:
            GLib.idle_add(_evt_char_ref.push,
                {"event": "bt_disconnected", "mac": mac})
            GLib.idle_add(_evt_char_ref.push, bt_list_trusted())
    threading.Thread(target=_do, daemon=True).start()


def bt_forget(mac):
    """Unpair + remove trust via host bluetoothctl."""
    def _do():
        _bt_write(f"BT_FORGET:{mac}")
        _bt_wait_result(10)
        if _evt_char_ref:
            GLib.idle_add(_evt_char_ref.push,
                {"event": "bt_disconnected", "mac": mac})
            GLib.idle_add(_evt_char_ref.push, bt_list_trusted())
    threading.Thread(target=_do, daemon=True).start()


# ── Advertisement ─────────────────────────────────────────────────────────────

class YTAdvertisement(dbus.service.Object):
    PATH = "/org/bluez/hci0/advertisement0"

    def __init__(self, bus):
        dbus.service.Object.__init__(self, bus, self.PATH)

    @dbus.service.method(PROP_IF, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return {
            "Type":           dbus.String("peripheral"),
            "LocalName":      dbus.String(DEVICE_NAME),
            "ServiceUUIDs":   dbus.Array([SERVICE_UUID], signature="s"),
            "IncludeTxPower": dbus.Boolean(True),
        }

    @dbus.service.method(ADV_IF)
    def Release(self):
        print("[BLE] Advertisement released", flush=True)


# ── EVT Characteristic (NOTIFY) ───────────────────────────────────────────────

class EvtCharacteristic(dbus.service.Object):
    PATH = "/org/bluez/hci0/service0/char1"

    def __init__(self, bus):
        self.notifying = False
        self._value    = dbus.Array([], signature='y')
        dbus.service.Object.__init__(self, bus, self.PATH)

    def get_props(self):
        return {
            "Service":   dbus.ObjectPath("/org/bluez/hci0/service0"),
            "UUID":      dbus.String(EVT_CHAR_UUID),
            "Flags":     dbus.Array(["notify"], signature="s"),
            "Notifying": dbus.Boolean(self.notifying),
        }

    @dbus.service.method(GATT_CHR)
    def StartNotify(self):
        if self.notifying:
            return
        self.notifying = True
        print("[BLE] EVT notify started", flush=True)
        # Push trusted devices — pure D-Bus read, zero audio disruption
        threading.Thread(
            target=lambda: self.push(bt_list_trusted()),
            daemon=True
        ).start()

    @dbus.service.method(GATT_CHR)
    def StopNotify(self):
        self.notifying = False
        print("[BLE] EVT notify stopped", flush=True)

    @dbus.service.signal(PROP_IF, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    def push(self, payload: dict):
        if not self.notifying:
            return
        try:
            msg = json.dumps(payload)
            self._value = dbus.Array(list(msg.encode('utf-8')), signature='y')
            self.PropertiesChanged(GATT_CHR, {'Value': self._value}, [])
        except Exception as e:
            print(f'[BLE] EVT push failed: {e}', flush=True)


# ── CMD Characteristic (WRITE) ────────────────────────────────────────────────

class CmdCharacteristic(dbus.service.Object):
    PATH = "/org/bluez/hci0/service0/char0"

    def __init__(self, bus, on_url, on_cmd, evt_char):
        self._on_url = on_url
        self._on_cmd = on_cmd
        self._evt    = evt_char
        dbus.service.Object.__init__(self, bus, self.PATH)

    def get_props(self):
        return {
            "Service": dbus.ObjectPath("/org/bluez/hci0/service0"),
            "UUID":    dbus.String(CMD_CHAR_UUID),
            "Flags":   dbus.Array(["write", "write-without-response"], signature="s"),
        }

    @dbus.service.method(GATT_CHR, in_signature="aya{sv}")
    def WriteValue(self, value, options):
        text = bytes(value).decode("utf-8", errors="ignore").strip()
        print(f"[BLE] Received: {text}", flush=True)

        if not text.startswith("CMD:"):
            GLib.idle_add(self._on_url, text)
            return

        cmd = text[4:].strip()

        if cmd == 'BT_SCAN_START':
            result = bt_scan_start(self._evt.push)
            self._evt.push(result)

        elif cmd == 'BT_SCAN_STOP':
            self._evt.push(bt_scan_stop())

        elif cmd == 'BT_LIST':
            threading.Thread(
                target=lambda: self._evt.push(bt_list_trusted()),
                daemon=True
            ).start()

        elif cmd.startswith('BT_PAIR:'):
            bt_pair(cmd[8:].strip())

        elif cmd.startswith('BT_CONNECT:'):
            bt_connect(cmd[11:].strip())

        elif cmd.startswith('BT_DISCONNECT:'):
            bt_disconnect(cmd[14:].strip())

        elif cmd.startswith('BT_FORGET:'):
            bt_forget(cmd[10:].strip())

        else:
            GLib.idle_add(self._on_cmd, text)

# ── Service ───────────────────────────────────────────────────────────────────

class YTService(dbus.service.Object):
    PATH = "/org/bluez/hci0/service0"

    def __init__(self, bus):
        dbus.service.Object.__init__(self, bus, self.PATH)

    @dbus.service.method(PROP_IF, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return {
            "UUID":    dbus.String(SERVICE_UUID),
            "Primary": dbus.Boolean(True),
        }


# ── GATT Application ──────────────────────────────────────────────────────────

class GATTApplication(dbus.service.Object):
    PATH = "/org/bluez/hci0/app"

    def __init__(self, bus, service, cmd_char, evt_char):
        self.service  = service
        self.cmd_char = cmd_char
        self.evt_char = evt_char
        dbus.service.Object.__init__(self, bus, self.PATH)

    @dbus.service.method(DBUS_OM, out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        return {
            dbus.ObjectPath(self.service.PATH):  {GATT_SVC: self.service.GetAll(GATT_SVC)},
            dbus.ObjectPath(self.cmd_char.PATH): {GATT_CHR: self.cmd_char.get_props()},
            dbus.ObjectPath(self.evt_char.PATH): {GATT_CHR: self.evt_char.get_props()},
        }


# ── BLE Server ────────────────────────────────────────────────────────────────

class BLEGattServer:
    def __init__(self, on_url, on_cmd, on_connected=None, on_disconnected=None):
        self._on_url          = on_url
        self._on_cmd          = on_cmd
        self._on_connected    = on_connected
        self._on_disconnected = on_disconnected
        self._ready = threading.Event()
        t = threading.Thread(target=self._run, daemon=True)
        t.start()
        self._ready.wait(timeout=10)
        if not self._ready.is_set():
            print("[BLE] Warning: did not start within 10s", flush=True)

    def _run(self):
        global _bus, _evt_char_ref

        os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = DBUS_SOCK
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

        try:
            _bus = dbus.SystemBus()
            print("[BLE] D-Bus connected", flush=True)
        except Exception as e:
            print(f"[BLE] D-Bus failed: {e}", flush=True)
            self._ready.set()
            return

        # Watch all device property changes — phone AND BT speakers
        _bus.add_signal_receiver(
            self._on_properties_changed,
            dbus_interface=PROP_IF,
            signal_name="PropertiesChanged",
            path_keyword="path",
        )

        # Watch for new devices appearing during scan
        _bus.add_signal_receiver(
            self._on_interfaces_added,
            dbus_interface=DBUS_OM,
            signal_name="InterfacesAdded",
        )

        try:
            adapter  = _bus.get_object(BLUEZ, ADAPTER_PATH)
            gatt_mgr = dbus.Interface(adapter, GATT_MGR)
            adv_mgr  = dbus.Interface(adapter, ADV_MGR)
        except Exception as e:
            print(f"[BLE] Adapter error: {e}", flush=True)
            self._ready.set()
            return

        evt_char = EvtCharacteristic(_bus)
        cmd_char = CmdCharacteristic(_bus, self._on_url, self._on_cmd, evt_char)
        svc      = YTService(_bus)
        app      = GATTApplication(_bus, svc, cmd_char, evt_char)
        adv      = YTAdvertisement(_bus)

        # Store evt_char reference for BT functions to push events
        _evt_char_ref = evt_char

        gatt_mgr.RegisterApplication(
            dbus.ObjectPath(app.PATH), {},
            reply_handler=lambda: print("[BLE] GATT registered", flush=True),
            error_handler=lambda e: print(f"[BLE] GATT error: {e}", flush=True),
        )
        adv_mgr.RegisterAdvertisement(
            dbus.ObjectPath(adv.PATH), {},
            reply_handler=lambda: (
                print(f"[BLE] Advertising as '{DEVICE_NAME}'", flush=True),
                self._ready.set(),
            ),
            error_handler=lambda e: (
                print(f"[BLE] Adv error: {e}", flush=True),
                self._ready.set(),
            ),
        )
        GLib.MainLoop().run()

    def _on_interfaces_added(self, path, interfaces):
        """New device found during scan — push to phone immediately."""
        if DEVICE_IF not in interfaces:
            return
        props = interfaces[DEVICE_IF]
        mac   = str(props.get("Address", ""))
        name  = str(props.get("Name", ""))
        trusted = bool(props.get("Trusted", False))
        rssi    = int(props.get("RSSI", 0))
        if not mac or not name or name == mac or trusted:
            return
        print(f"[BT] New device found: {name} ({mac})", flush=True)
        if _evt_char_ref:
            # Push updated scan results
            devices = _get_all_devices()
            available = [
                {"mac": d["mac"], "name": d["name"], "rssi": d["rssi"]}
                for d in devices.values()
                if not d["trusted"] and d["name"] != d["mac"] and d["name"]
            ]
            _evt_char_ref.push({
                "event": "bt_scan_results",
                "devices": available
            })

    def _on_properties_changed(self, interface, changed, invalidated, path):
        """Handle connect/disconnect for both phone and BT audio devices."""
        if interface != DEVICE_IF:
            return
        if "Connected" not in changed:
            return

        connected = bool(changed["Connected"])

        # Get device info
        try:
            props = dbus.Interface(
                _bus.get_object(BLUEZ, path),
                PROP_IF
            )
            name    = str(props.Get(DEVICE_IF, "Name"))
            trusted = bool(props.Get(DEVICE_IF, "Trusted"))
            mac     = str(props.Get(DEVICE_IF, "Address"))
        except Exception:
            name    = "Unknown"
            trusted = False
            mac     = str(path).split("/")[-1].replace("_", ":").upper()

        if connected:
            print(f"[BLE] Connected: {name} ({mac}) trusted={trusted}", flush=True)
            if trusted:
                # BT audio device connected — push updated trusted list
                if _evt_char_ref:
                    _evt_char_ref.push({"event": "bt_connected",
                                       "mac": mac, "name": name})
                    _evt_char_ref.push(bt_list_trusted())
            else:
                # Phone connected
                if self._on_connected:
                    GLib.idle_add(self._on_connected, name)
        else:
            print(f"[BLE] Disconnected: {name} ({mac}) trusted={trusted}", flush=True)
            if trusted:
                # BT audio device disconnected — push updated trusted list
                if _evt_char_ref:
                    _evt_char_ref.push({"event": "bt_disconnected", "mac": mac})
                    _evt_char_ref.push(bt_list_trusted())
            else:
                # Phone disconnected
                if self._on_disconnected:
                    GLib.idle_add(self._on_disconnected)
