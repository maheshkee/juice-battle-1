# ble_scanner.py — BLE GATT client for remote PIR sensors
import os, sys, ctypes, threading, time
from config import WHEELS_DIR, TYPELIBS_DIR, SHARED_LIBS, REMOTE_SENSORS

os.environ["GI_TYPELIB_PATH"] = TYPELIBS_DIR
for lib in SHARED_LIBS:
    try: ctypes.CDLL(f"{WHEELS_DIR}/{lib}")
    except: pass
sys.path.insert(0, "/usr/lib/python3/dist-packages")

import dbus, dbus.mainloop.glib
from gi.repository import GLib

BLUEZ     = "org.bluez"
DEVICE_IF = "org.bluez.Device1"
ADAPTER_IF= "org.bluez.Adapter1"
GATT_CHR  = "org.bluez.GattCharacteristic1"
PROP_IF   = "org.freedesktop.DBus.Properties"
DBUS_OM   = "org.freedesktop.DBus.ObjectManager"


def _mac_to_path(mac):
    return "/org/bluez/hci0/dev_" + mac.replace(":", "_")


def _device_exists(bus, mac):
    """Check if BlueZ has this device in its cache."""
    try:
        om = dbus.Interface(bus.get_object(BLUEZ, "/"), DBUS_OM)
        objects = om.GetManagedObjects()
        path = _mac_to_path(mac)
        return path in objects
    except:
        return False


def _discover_device(bus, mac, timeout=30):
    """Start discovery and wait until device appears in BlueZ cache."""
    adapter_obj   = bus.get_object(BLUEZ, "/org/bluez/hci0")
    adapter_iface = dbus.Interface(adapter_obj, ADAPTER_IF)

    print(f"[SCAN] Starting discovery to find {mac}...", flush=True)
    try:
        adapter_iface.StartDiscovery()
    except Exception as e:
        print(f"[SCAN] StartDiscovery: {e}", flush=True)

    found = False
    for i in range(timeout):
        if _device_exists(bus, mac):
            found = True
            print(f"[SCAN] Device {mac} found in BlueZ cache", flush=True)
            break
        time.sleep(1)

    try:
        adapter_iface.StopDiscovery()
    except:
        pass

    return found


class RemoteSensor:
    def __init__(self, name, mac, char_uuid, on_change):
        self.name      = name
        self.mac       = mac
        self.char_uuid = char_uuid
        self.on_change = on_change
        self.bus       = None
        self.char_path = None

    def start(self, bus):
        self.bus = bus
        threading.Thread(target=self._connect_loop, daemon=True).start()

    def _connect_loop(self):
        while True:
            try:
                self._connect_and_subscribe()
                return
            except Exception as e:
                print(f"[SCAN] {self.name} error: {e} — retry in 15s", flush=True)
                time.sleep(15)

    def _connect_and_subscribe(self):
        # Step 1 — ensure device is in BlueZ cache
        if not _device_exists(self.bus, self.mac):
            found = _discover_device(self.bus, self.mac)
            if not found:
                raise Exception(f"Device {self.mac} not found during discovery")

        device_path = _mac_to_path(self.mac)
        dev_obj     = self.bus.get_object(BLUEZ, device_path)
        dev_iface   = dbus.Interface(dev_obj, DEVICE_IF)
        props       = dbus.Interface(dev_obj, PROP_IF)

        # Step 2 — connect if not connected
        try:
            connected = bool(props.Get(DEVICE_IF, "Connected"))
        except:
            connected = False

        if not connected:
            print(f"[SCAN] Connecting to {self.name}...", flush=True)
            dev_iface.Connect()
            time.sleep(3)

        # Step 3 — wait for services to resolve
        print(f"[SCAN] Waiting for GATT services...", flush=True)
        for _ in range(15):
            try:
                if bool(props.Get(DEVICE_IF, "ServicesResolved")):
                    break
            except:
                pass
            time.sleep(1)

        # Step 4 — find characteristic by UUID
        self.char_path = self._find_char(device_path)
        if not self.char_path:
            raise Exception(f"Characteristic {self.char_uuid} not found")

        # Step 5 — enable notifications
        char_obj   = self.bus.get_object(BLUEZ, self.char_path)
        char_iface = dbus.Interface(char_obj, GATT_CHR)
        char_iface.StartNotify()
        print(f"[SCAN] {self.name} ready — listening for motion", flush=True)

        # Step 6 — register signal receiver
        self.bus.add_signal_receiver(
            self._on_changed,
            dbus_interface=PROP_IF,
            signal_name="PropertiesChanged",
            path=self.char_path,
        )

    def _find_char(self, device_path):
        om = dbus.Interface(
            self.bus.get_object(BLUEZ, "/"), DBUS_OM)
        objects = om.GetManagedObjects()
        for path, ifaces in objects.items():
            if GATT_CHR not in ifaces:
                continue
            if not str(path).startswith(device_path):
                continue
            uuid = str(ifaces[GATT_CHR].get("UUID", ""))
            if uuid.lower() == self.char_uuid.lower():
                print(f"[SCAN] Found char: {path}", flush=True)
                return str(path)
        return None

    def _on_changed(self, interface, changed, invalidated):
        if interface != GATT_CHR:
            return
        if "Value" not in changed:
            return
        value = list(changed["Value"])
        if not value:
            return
        state = (value[0] == 0x01)
        print(f"[SCAN] {self.name} -> {"DETECTED" if state else "CLEAR"}", flush=True)
        self.on_change(self.name, state)


class BLEScanner:
    def __init__(self, on_remote_motion):
        self.on_remote_motion = on_remote_motion
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def _run(self):
        os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = "unix:path=/app/dbus.sock"
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        try:
            bus = dbus.SystemBus()
            print("[SCAN] Scanner bus connected", flush=True)
        except Exception as e:
            print(f"[SCAN] Bus error: {e}", flush=True)
            return

        for name, cfg in REMOTE_SENSORS.items():
            sensor = RemoteSensor(
                name=name,
                mac=cfg["mac"],
                char_uuid=cfg["char_uuid"],
                on_change=self.on_remote_motion
            )
            sensor.start(bus)

        GLib.MainLoop().run()
