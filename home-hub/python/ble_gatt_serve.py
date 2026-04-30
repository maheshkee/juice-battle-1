# ble_gatt_serve.py — BLE Peripheral GATT server for home-hub
# GATT core only. BT audio functions live in bt_manager.py.
#
# Service UUID:   a01c0000-0000-0000-0000-000000000000
# CMD Char UUID:  a01c0001-0000-0000-0000-000000000000  (WRITE)
# EVT Char UUID:  a01c0002-0000-0000-0000-000000000000  (NOTIFY)
#
# CMD write protocol:
#   Raw YouTube URL             -> on_url()
#   CMD:PAUSE/RESUME/STOP/...   -> on_cmd()
#   CMD:BT_*                    -> bt_manager functions
#   CMD:QUEUE_*                 -> queue_engine functions (v1.3)
#   CMD:LOCAL_*                 -> local_engine functions (v1.3)

import os, sys, ctypes, threading, json

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

import bt_manager

BLUEZ     = "org.bluez"
ADV_IF    = "org.bluez.LEAdvertisement1"
ADV_MGR   = "org.bluez.LEAdvertisingManager1"
PROP_IF   = "org.freedesktop.DBus.Properties"
GATT_MGR  = "org.bluez.GattManager1"
GATT_SVC  = "org.bluez.GattService1"
GATT_CHR  = "org.bluez.GattCharacteristic1"
DBUS_OM   = "org.freedesktop.DBus.ObjectManager"
DEVICE_IF = "org.bluez.Device1"

SERVICE_UUID  = "a01c0000-0000-0000-0000-000000000000"
CMD_CHAR_UUID = "a01c0001-0000-0000-0000-000000000000"
EVT_CHAR_UUID = "a01c0002-0000-0000-0000-000000000000"
DEVICE_NAME   = "YT-Display"
ADAPTER_PATH  = "/org/bluez/hci0"


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
        threading.Thread(
            target=lambda: self.push(bt_manager.bt_list_trusted()),
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

        # ── BT audio commands ──────────────────────────────────────────────
        if cmd == 'BT_SCAN_START':
            result = bt_manager.bt_scan_start(self._evt.push)
            self._evt.push(result)

        elif cmd == 'BT_SCAN_STOP':
            self._evt.push(bt_manager.bt_scan_stop())

        elif cmd == 'BT_LIST':
            threading.Thread(
                target=lambda: self._evt.push(bt_manager.bt_list_trusted()),
                daemon=True
            ).start()

        elif cmd.startswith('BT_PAIR:'):
            bt_manager.bt_pair(cmd[8:].strip())

        elif cmd.startswith('BT_CONNECT:'):
            bt_manager.bt_connect(cmd[11:].strip())

        elif cmd.startswith('BT_DISCONNECT:'):
            bt_manager.bt_disconnect(cmd[14:].strip())

        elif cmd.startswith('BT_FORGET:'):
            bt_manager.bt_forget(cmd[10:].strip())

        # ── Queue commands (v1.3) — handled by main.py via on_cmd ─────────
        elif cmd.startswith('QUEUE_'):
            GLib.idle_add(self._on_cmd, text)

        # ── Local storage commands (v1.3) — handled by main.py via on_cmd ─
        elif cmd.startswith('LOCAL_'):
            GLib.idle_add(self._on_cmd, text)

        # ── Playback + other commands ──────────────────────────────────────
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

    def push_evt(self, payload: dict):
        """Push event to phone via BLE EVT characteristic."""
        evt = bt_manager._evt_char_ref
        if evt:
            evt.push(payload)

    def _run(self):
        os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = DBUS_SOCK
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

        try:
            bus = dbus.SystemBus()
            print("[BLE] D-Bus connected", flush=True)
        except Exception as e:
            print(f"[BLE] D-Bus failed: {e}", flush=True)
            self._ready.set()
            return

        # Share bus with bt_manager
        bt_manager.set_bus(bus)

        # Watch device property changes
        bus.add_signal_receiver(
            self._on_properties_changed,
            dbus_interface=PROP_IF,
            signal_name="PropertiesChanged",
            path_keyword="path",
        )
        bus.add_signal_receiver(
            self._on_interfaces_added,
            dbus_interface=DBUS_OM,
            signal_name="InterfacesAdded",
        )

        try:
            adapter  = bus.get_object(BLUEZ, ADAPTER_PATH)
            gatt_mgr = dbus.Interface(adapter, GATT_MGR)
            adv_mgr  = dbus.Interface(adapter, ADV_MGR)
        except Exception as e:
            print(f"[BLE] Adapter error: {e}", flush=True)
            self._ready.set()
            return

        evt_char = EvtCharacteristic(bus)
        cmd_char = CmdCharacteristic(bus, self._on_url, self._on_cmd, evt_char)
        svc      = YTService(bus)
        app      = GATTApplication(bus, svc, cmd_char, evt_char)
        adv      = YTAdvertisement(bus)

        # Share evt_char with bt_manager
        bt_manager.set_evt_char(evt_char)

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
        if DEVICE_IF not in interfaces:
            return
        props   = interfaces[DEVICE_IF]
        mac     = str(props.get("Address", ""))
        name    = str(props.get("Name", ""))
        trusted = bool(props.get("Trusted", False))
        rssi    = int(props.get("RSSI", 0))
        if not mac or not name or name == mac or trusted:
            return
        print(f"[BT] New device found: {name} ({mac})", flush=True)
        evt_char = bt_manager._evt_char_ref
        if evt_char:
            devices  = bt_manager.get_all_devices()
            available = [
                {"mac": d["mac"], "name": d["name"], "rssi": d["rssi"]}
                for d in devices.values()
                if not d["trusted"] and d["name"] != d["mac"] and d["name"]
            ]
            evt_char.push({"event": "bt_scan_results", "devices": available})

    def _on_properties_changed(self, interface, changed, invalidated, path):
        if interface != DEVICE_IF:
            return
        if "Connected" not in changed:
            return

        connected = bool(changed["Connected"])
        try:
            props   = dbus.Interface(
                bt_manager._bus.get_object(BLUEZ, path), PROP_IF
            )
            name    = str(props.Get(DEVICE_IF, "Name"))
            trusted = bool(props.Get(DEVICE_IF, "Trusted"))
            mac     = str(props.Get(DEVICE_IF, "Address"))
        except Exception:
            name    = "Unknown"
            trusted = False
            mac     = str(path).split("/")[-1].replace("_", ":").upper()

        evt_char = bt_manager._evt_char_ref
        if connected:
            print(f"[BLE] Connected: {name} ({mac}) trusted={trusted}", flush=True)
            if trusted:
                if evt_char:
                    evt_char.push({"event": "bt_connected", "mac": mac, "name": name})
                    evt_char.push(bt_manager.bt_list_trusted())
            else:
                if self._on_connected:
                    GLib.idle_add(self._on_connected, name)
        else:
            print(f"[BLE] Disconnected: {name} ({mac}) trusted={trusted}", flush=True)
            if trusted:
                if evt_char:
                    evt_char.push({"event": "bt_disconnected", "mac": mac})
                    evt_char.push(bt_manager.bt_list_trusted())
            else:
                if self._on_disconnected:
                    GLib.idle_add(self._on_disconnected)
