# ble_gatt_server.py — BLE Peripheral (GATT server) for youtube-display
# Board advertises, phone scans, connects, and writes URL + commands.
#
# Service UUID:  a01c0000-0000-0000-0000-000000000000
# CMD Char UUID: a01c0001-0000-0000-0000-000000000000  (WRITE)
#
# Write protocol:
#   Raw YouTube URL  -> passed to on_url_received()
#   "CMD:PAUSE"      -> passed to on_cmd_received()
#   "CMD:RESUME"     -> passed to on_cmd_received()
#   "CMD:STOP"       -> passed to on_cmd_received()
#   "CMD:VOL_UP"     -> passed to on_cmd_received()
#   "CMD:VOL_DOWN"   -> passed to on_cmd_received()

import os, sys, ctypes, threading

# ── D-Bus / BlueZ setup ───────────────────────────────────────────────────────

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

# ── BlueZ D-Bus interfaces ────────────────────────────────────────────────────

BLUEZ    = "org.bluez"
ADV_IF   = "org.bluez.LEAdvertisement1"
ADV_MGR  = "org.bluez.LEAdvertisingManager1"
PROP_IF  = "org.freedesktop.DBus.Properties"
GATT_MGR = "org.bluez.GattManager1"
GATT_SVC = "org.bluez.GattService1"
GATT_CHR = "org.bluez.GattCharacteristic1"
DBUS_OM  = "org.freedesktop.DBus.ObjectManager"

# ── UUIDs ─────────────────────────────────────────────────────────────────────

SERVICE_UUID = "a01c0000-0000-0000-0000-000000000000"
CMD_CHAR_UUID = "a01c0001-0000-0000-0000-000000000000"
DEVICE_NAME  = "YT-Display"

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

# ── CMD Characteristic (WRITE) ────────────────────────────────────────────────

class CmdCharacteristic(dbus.service.Object):
    PATH = "/org/bluez/hci0/service0/char0"

    def __init__(self, bus, on_url, on_cmd):
        self._on_url = on_url
        self._on_cmd = on_cmd
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
        if text.startswith("CMD:"):
            GLib.idle_add(self._on_cmd, text)
        else:
            GLib.idle_add(self._on_url, text)

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

    def __init__(self, bus, service, char):
        self.service = service
        self.char    = char
        dbus.service.Object.__init__(self, bus, self.PATH)

    @dbus.service.method(DBUS_OM, out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        return {
            dbus.ObjectPath(self.service.PATH): {GATT_SVC: self.service.GetAll(GATT_SVC)},
            dbus.ObjectPath(self.char.PATH):    {GATT_CHR: self.char.get_props()},
        }

# ── BLE Manager ───────────────────────────────────────────────────────────────

class BLEGattServer:
    """
    Peripheral GATT server for youtube-display.
    Advertises as YT-Display, receives URL and CMD writes from phone.

    Usage:
        server = BLEGattServer(on_url_received, on_cmd_received)
        # callbacks fire on GLib thread — use GLib.idle_add if touching UI/state
    """

    def __init__(self, on_url, on_cmd):
        self._on_url  = on_url
        self._on_cmd  = on_cmd
        self._ready   = threading.Event()
        t = threading.Thread(target=self._run, daemon=True)
        t.start()
        self._ready.wait(timeout=10)
        if not self._ready.is_set():
            print("[BLE] Warning: did not start within 10s", flush=True)

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

        try:
            adapter  = bus.get_object(BLUEZ, "/org/bluez/hci0")
            gatt_mgr = dbus.Interface(adapter, GATT_MGR)
            adv_mgr  = dbus.Interface(adapter, ADV_MGR)
        except Exception as e:
            print(f"[BLE] Adapter error: {e}", flush=True)
            self._ready.set()
            return

        char = CmdCharacteristic(bus, self._on_url, self._on_cmd)
        svc  = YTService(bus)
        app  = GATTApplication(bus, svc, char)
        adv  = YTAdvertisement(bus)

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
