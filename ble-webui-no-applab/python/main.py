import sys, os, threading, logging
logging.basicConfig(level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s")
log=logging.getLogger("main")
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))

from state import AppState
from bridge import ArduinoBridge
from ble_server import BLEServer
import web_handler

state=AppState(); bridge=ArduinoBridge(); ble=None

def on_ble_write(led_state):
    log.info("BLE write: led=%s", led_state)
    state.add_event("ble_write",{"value":1 if led_state else 0,
        "desc":"phone wrote "+("1 - LED ON" if led_state else "0 - LED OFF")})
    def do_call():
        result=bridge.call("set_led",[led_state])
        log.info("MCU response: %s", result)
        state.update_led(led_state, source="ble")
        state.add_event("mcu_response",{"method":"set_led","result":str(result),
            "desc":"MCU confirmed LED="+str(result)})
        if ble: ble.send_notify(led_state)
    threading.Thread(target=do_call, daemon=True).start()

def get_ip():
    import socket
    try:
        s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        s.connect(("8.8.8.8",80)); ip=s.getsockname()[0]; s.close(); return ip
    except: return "board-ip"

def main():
    global ble
    log.info("Connecting to bridge...")
    bridge.connect()
    state.add_event("system",{"desc":"Bridge connected to MCU"})
    web_handler.init(state)
    threading.Thread(target=lambda:web_handler.run("0.0.0.0",5000),daemon=True).start()
    state.add_event("system",{"desc":"Web server started on port 5000"})
    ble=BLEServer(on_write_cb=on_ble_write)
    mainloop=ble.setup()
    ip=get_ip()
    log.info("============================================")
    log.info("  BLE WebUI v1 running")
    log.info("  Web UI  : http://%s:5000", ip)
    log.info("  BLE name: UNO-Q-BLE")
    log.info("  Write 01 to LED char -> LED ON")
    log.info("  Write 00 to LED char -> LED OFF")
    log.info("============================================")
    state.add_event("system",{"desc":"BLE advertising as UNO-Q-BLE"})
    mainloop.run()

if __name__=="__main__": main()
