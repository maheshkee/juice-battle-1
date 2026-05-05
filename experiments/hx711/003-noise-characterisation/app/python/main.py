from arduino.app_utils import App, Bridge

def on_log(data):
    print(f"[MCU] {data}", flush=True)

def on_cal(data):
    print(f"[CAL] {data}", flush=True)

def on_noise(data):
    print(f"[NOISE] {data}", flush=True)

def on_delta(data):
    print(f"[DELTA] {data}", flush=True)

def on_detection(data):
    print(f"[DETECTED] *** {data} ***", flush=True)

Bridge.provide("log", on_log)
Bridge.provide("cal_result", on_cal)
Bridge.provide("noise_result", on_noise)
Bridge.provide("delta_reading", on_delta)
Bridge.provide("detection_event", on_detection)

App.run()
