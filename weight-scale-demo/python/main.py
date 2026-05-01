import time
from arduino.app_utils import App
from arduino.app_utils import Bridge
from arduino.app_utils import UI

bridge = Bridge()
ui = UI()

def loop():
    try:
        weight = bridge.call("get_weight")
        print("Weight:", weight)

        # send to WebUI
        ui.send_message("weight_update", {
            "weight": weight
        })

    except Exception as e:
        print("Error:", e)

    time.sleep(1)

App.run(user_loop=loop)