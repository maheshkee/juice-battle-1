from arduino.app_utils import App, Bridge
from arduino.app_bricks.web_ui import WebUI
import threading, time, json

ui = WebUI()

def weight_poll_loop():
    import concurrent.futures
    print("[WEIGHT] polling started", flush=True)
    while True:
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
                result = ex.submit(Bridge.call, "read_weight_packet").result(timeout=5)
            data = json.loads(result)
            print(f"[WEIGHT] {result}", flush=True)
            if data.get("ok"):
                ui.send_message("weight_update", {
                    "grams":  data.get("grams",  0.0),
                    "raw":    data.get("raw",    0),
                    "stable": data.get("stable", False)
                })
        except Exception as e:
            print(f"[WEIGHT] error: {e}", flush=True)
        time.sleep(2)

threading.Thread(target=weight_poll_loop, daemon=True).start()
App.run()
