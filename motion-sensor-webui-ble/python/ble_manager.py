# ble_manager.py — BLE advertisement and GATT server
import os, sys, ctypes, threading
from config import (APP_NAME, BLE_SERVICE_UUID, MANUFACTURER_ID,
                    DBUS_SOCK, WHEELS_DIR, TYPELIBS_DIR, SHARED_LIBS)

def _load_libs():
    os.environ["GI_TYPELIB_PATH"] = TYPELIBS_DIR
    for lib in SHARED_LIBS:
        try:
            ctypes.CDLL(f"{WHEELS_DIR}/{lib}")
        except Exception as e:
            print(f"[LIB] {lib}: {e}", flush=True)
    sys.path.insert(0, "/usr/lib/python3/dist-packages")
    print("[LIB] Libraries loaded", flush=True)

_load_libs()

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

BLUEZ   = "org.bluez"
ADV_IF  = "org.bluez.LEAdvertisement1"
ADV_MGR = "org.bluez.LEAdvertisingManager1"
PROP_IF = "org.freedesktop.DBus.Properties"
GATT_MGR= "org.bluez.GattManager1"
GATT_SVC= "org.bluez.GattService1"
GATT_CHR= "org.bluez.GattCharacteristic1"
DBUS_OM = "org.freedesktop.DBus.ObjectManager"


class MotionAdvertisement(dbus.service.Object):
    PATH = "/org/bluez/hci0/advertisement0"

    def __init__(self, bus):
        self.motion = False
        dbus.service.Object.__init__(self, bus, self.PATH)

    @dbus.service.method(PROP_IF, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return {
            "Type":       dbus.String("peripheral"),
            "LocalName":  dbus.String(APP_NAME),
            "ServiceUUIDs": dbus.Array([BLE_SERVICE_UUID], signature="s"),
            "ManufacturerData": dbus.Dictionary(
                {dbus.UInt16(MANUFACTURER_ID): dbus.Array(
                    [dbus.Byte(0x01 if self.motion else 0x00)],
                    signature="y")},
                signature="qv"),
            "IncludeTxPower": dbus.Boolean(True),
        }

    @dbus.service.method(ADV_IF)
    def Release(self):
        print("[BLE] Advertisement released", flush=True)


class MotionCharacteristic(dbus.service.Object):
    """GATT characteristic — phone can read motion state or get notified."""
    PATH = "/org/bluez/hci0/service0/char0"

    def __init__(self, bus):
        self.motion = False
        self.notifying = False
        dbus.service.Object.__init__(self, bus, self.PATH)

    def get_props(self):
        return {
            "Service":  dbus.ObjectPath("/org/bluez/hci0/service0"),
            "UUID":     dbus.String("a00b0001-0000-0000-0000-000000000000"),
            "Flags":    dbus.Array(["read","notify"], signature="s"),
            "Notifying":dbus.Boolean(self.notifying),
            "Value":    dbus.Array([dbus.Byte(0x01 if self.motion else 0x00)], signature="y"),
        }

    @dbus.service.method(GATT_CHR, in_signature="a{sv}", out_signature="ay")
    def ReadValue(self, options):
        val = 0x01 if self.motion else 0x00
        print(f"[BLE] Phone read motion: {val}", flush=True)
        return dbus.Array([dbus.Byte(val)], signature="y")

    @dbus.service.method(GATT_CHR)
    def StartNotify(self):
        self.notifying = True
        print("[BLE] Phone subscribed to notifications", flush=True)

    @dbus.service.method(GATT_CHR)
    def StopNotify(self):
        self.notifying = False
        print("[BLE] Phone unsubscribed", flush=True)

    @dbus.service.signal(PROP_IF, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    def notify_motion(self, state):
        """Push new value to subscribed phone."""
        self.motion = state
        val = dbus.Array([dbus.Byte(0x01 if state else 0x00)], signature="y")
        self.PropertiesChanged(GATT_CHR, {"Value": val}, [])
        print(f"[BLE] Notified phone: {"DETECTED" if state else "CLEAR"}", flush=True)


class MotionService(dbus.service.Object):
    PATH = "/org/bluez/hci0/service0"

    def __init__(self, bus, char):
        self.char = char
        dbus.service.Object.__init__(self, bus, self.PATH)

    @dbus.service.method(PROP_IF, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return {
            "UUID":    dbus.String(BLE_SERVICE_UUID),
            "Primary": dbus.Boolean(True),
        }


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


class BLEManager:
    def __init__(self):
        self._adv   = None
        self._char  = None
        self._loop  = None
        self._ready = threading.Event()
        t = threading.Thread(target=self._run, daemon=True)
        t.start()
        self._ready.wait(timeout=10)
        if not self._ready.is_set():
            print("[BLE] Warning: BLE did not start within 10s", flush=True)

    def _run(self):
        os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = DBUS_SOCK
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        try:
            bus = dbus.SystemBus()
            print("[BLE] SystemBus connected", flush=True)
        except Exception as e:
            print(f"[BLE] SystemBus failed: {e}", flush=True)
            return
        try:
            adapter  = bus.get_object(BLUEZ, "/org/bluez/hci0")
            adv_mgr  = dbus.Interface(adapter, ADV_MGR)
            gatt_mgr = dbus.Interface(adapter, GATT_MGR)
        except Exception as e:
            print(f"[BLE] Adapter error: {e}", flush=True)
            return

        self._char = MotionCharacteristic(bus)
        svc        = MotionService(bus, self._char)
        app        = GATTApplication(bus, svc, self._char)
        self._adv  = MotionAdvertisement(bus)

        gatt_mgr.RegisterApplication(
            dbus.ObjectPath(app.PATH), {},
            reply_handler=lambda: print("[BLE] GATT registered", flush=True),
            error_handler=lambda e: print(f"[BLE] GATT error: {e}", flush=True)
        )
        adv_mgr.RegisterAdvertisement(
            dbus.ObjectPath(self._adv.PATH), {},
            reply_handler=lambda: (
                print("[BLE] Advertising — scan for AQ2-Motion", flush=True),
                self._ready.set()
            ),
            error_handler=lambda e: (
                print(f"[BLE] Adv error: {e}", flush=True),
                self._ready.set()
            )
        )
        self._loop = GLib.MainLoop()
        self._loop.run()

    def update(self, state: bool):
        """Call this when motion state changes."""
        if self._adv:
            self._adv.motion = state
        if self._char and self._char.notifying:
            GLib.idle_add(self._char.notify_motion, state)
