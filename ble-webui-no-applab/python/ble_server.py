import dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib
import logging

log = logging.getLogger("ble")
BLUEZ="org.bluez"; ADAPTER_IF="org.bluez.Adapter1"
GATT_MGR_IF="org.bluez.GattManager1"; AD_MGR_IF="org.bluez.LEAdvertisingManager1"
AD_IF="org.bluez.LEAdvertisement1"; SVC_IF="org.bluez.GattService1"
CHAR_IF="org.bluez.GattCharacteristic1"; OM_IF="org.freedesktop.DBus.ObjectManager"
PROP_IF="org.freedesktop.DBus.Properties"
SVC_UUID="0000ffe0-0000-1000-8000-00805f9b34fb"
LED_UUID="0000ffe1-0000-1000-8000-00805f9b34fb"
STAT_UUID="0000ffe2-0000-1000-8000-00805f9b34fb"

class Advertisement(dbus.service.Object):
    def __init__(self, bus):
        self.path="/com/arduino/blewebui/ad0"
        dbus.service.Object.__init__(self, bus, self.path)
    def get_path(self): return dbus.ObjectPath(self.path)
    @dbus.service.method(PROP_IF, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return {"Type":dbus.String("peripheral"),
                "ServiceUUIDs":dbus.Array([SVC_UUID],signature="s"),
                "LocalName":dbus.String("UNO-Q-BLE"),
                "IncludeTxPower":dbus.Boolean(True)}
    @dbus.service.method(AD_IF)
    def Release(self): log.info("Ad released")

class Application(dbus.service.Object):
    def __init__(self, bus):
        self.path="/"; self._services=[]
        dbus.service.Object.__init__(self, bus, self.path)
    def get_path(self): return dbus.ObjectPath(self.path)
    def add_service(self, s): self._services.append(s)
    @dbus.service.method(OM_IF, out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        r={}
        for s in self._services:
            r[s.get_path()]=s.get_props()
            for c in s.chars: r[c.get_path()]=c.get_props()
        return r

class Service(dbus.service.Object):
    def __init__(self, bus):
        self.path="/com/arduino/blewebui/svc0"; self.chars=[]
        dbus.service.Object.__init__(self, bus, self.path)
    def get_path(self): return dbus.ObjectPath(self.path)
    def get_props(self):
        return {SVC_IF:{"UUID":dbus.String(SVC_UUID),"Primary":dbus.Boolean(True),
                "Characteristics":dbus.Array([c.get_path() for c in self.chars],signature="o")}}
    @dbus.service.method(PROP_IF, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface): return self.get_props().get(iface,{})

class LedChar(dbus.service.Object):
    def __init__(self, bus, svc, on_write):
        self.path=svc.path+"/char0"; self._svc=svc
        self._val=[dbus.Byte(0)]; self._notifying=False; self._on_write=on_write
        dbus.service.Object.__init__(self, bus, self.path)
    def get_path(self): return dbus.ObjectPath(self.path)
    def get_props(self):
        return {CHAR_IF:{"Service":self._svc.get_path(),"UUID":dbus.String(LED_UUID),
                "Flags":dbus.Array(["write","write-without-response","notify"],signature="s"),
                "Value":dbus.Array(self._val,signature="y")}}
    @dbus.service.method(PROP_IF, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface): return self.get_props().get(iface,{})
    @dbus.service.method(CHAR_IF, in_signature="a{sv}")
    def ReadValue(self, opts): return self._val
    @dbus.service.method(CHAR_IF, in_signature="aya{sv}")
    def WriteValue(self, value, opts):
        self._val=value
        if value:
            b=int(value[0]); state=(b==1 or b==49)
            log.info("BLE write: %s -> led=%s", b, state)
            if self._on_write: self._on_write(state)
    @dbus.service.method(CHAR_IF)
    def StartNotify(self): self._notifying=True
    @dbus.service.method(CHAR_IF)
    def StopNotify(self): self._notifying=False
    @dbus.service.signal(PROP_IF, signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, inv): pass
    def notify(self, state):
        v=[dbus.Byte(1 if state else 0)]; self._val=v
        if self._notifying:
            self.PropertiesChanged(CHAR_IF,{"Value":dbus.Array(v,signature="y")},[])

class StatusChar(dbus.service.Object):
    def __init__(self, bus, svc):
        self.path=svc.path+"/char1"; self._svc=svc
        self._val=[dbus.Byte(0)]; self._notifying=False
        dbus.service.Object.__init__(self, bus, self.path)
    def get_path(self): return dbus.ObjectPath(self.path)
    def get_props(self):
        return {CHAR_IF:{"Service":self._svc.get_path(),"UUID":dbus.String(STAT_UUID),
                "Flags":dbus.Array(["read","notify"],signature="s"),
                "Value":dbus.Array(self._val,signature="y")}}
    @dbus.service.method(PROP_IF, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface): return self.get_props().get(iface,{})
    @dbus.service.method(CHAR_IF, in_signature="a{sv}")
    def ReadValue(self, opts): return self._val
    @dbus.service.method(CHAR_IF)
    def StartNotify(self): self._notifying=True
    @dbus.service.method(CHAR_IF)
    def StopNotify(self): self._notifying=False
    @dbus.service.signal(PROP_IF, signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, inv): pass
    def notify(self, state):
        v=[dbus.Byte(1 if state else 0)]; self._val=v
        if self._notifying:
            self.PropertiesChanged(CHAR_IF,{"Value":dbus.Array(v,signature="y")},[])

class BLEServer:
    def __init__(self, on_write_cb):
        self._on_write_cb=on_write_cb
        self.led_char=None; self.stat_char=None; self.mainloop=None
    def setup(self):
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus=dbus.SystemBus()
        ap=self._find_adapter(bus)
        if not ap: raise RuntimeError("No BLE adapter found")
        ao=bus.get_object(BLUEZ,ap)
        dbus.Interface(ao,PROP_IF).Set(ADAPTER_IF,"Powered",dbus.Boolean(True))
        gm=dbus.Interface(ao,GATT_MGR_IF); am=dbus.Interface(ao,AD_MGR_IF)
        app=Application(bus); svc=Service(bus)
        self.led_char=LedChar(bus,svc,self._on_write_cb)
        self.stat_char=StatusChar(bus,svc)
        svc.chars=[self.led_char,self.stat_char]
        app.add_service(svc); ad=Advertisement(bus)
        self.mainloop=GLib.MainLoop()
        gm.RegisterApplication(app.get_path(),{},
            reply_handler=lambda:log.info("GATT registered"),
            error_handler=lambda e:log.error("GATT error: %s",e))
        am.RegisterAdvertisement(ad.get_path(),{},
            reply_handler=lambda:log.info("Advertising as UNO-Q-BLE"),
            error_handler=lambda e:log.error("Ad error: %s",e))
        return self.mainloop
    def send_notify(self, state):
        if self.led_char: self.led_char.notify(state)
        if self.stat_char: self.stat_char.notify(state)
    def _find_adapter(self, bus):
        om=dbus.Interface(bus.get_object(BLUEZ,"/"),OM_IF)
        for path,props in om.GetManagedObjects().items():
            if GATT_MGR_IF in props: return path
        return None
