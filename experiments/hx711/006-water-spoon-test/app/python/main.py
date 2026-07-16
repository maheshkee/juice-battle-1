import os
import time
import json
from arduino.app_utils import App, Bridge

TRIGGER      = "/app/trigger.txt"
WEIGHT_FILE  = "/app/known_weight.txt"
RESULTS_PATH = "/app/RESULTS_A.json"

TRIGGER_CMD = "touch ~/ArduinoApps/hx711-006-water-spoon-a/trigger.txt"
WEIGHT_CMD  = 'echo "<grams>" > ~/ArduinoApps/hx711-006-water-spoon-a/known_weight.txt'

STATES = ["await_mcu", "await_known_weight", "await_tare",
          "await_w1", "await_w2", "await_w3", "done"]

ctx = {
    "state": "await_mcu",
    "known_g": None,
    "raw_zero": None,
    "cal_factor": None,
    "readings": []
}


def step(msg):
    print(f">>> ACTION: {msg}", flush=True)


def read_weight_file():
    with open(WEIGHT_FILE) as f:
        val = float(f.read().strip())
    os.remove(WEIGHT_FILE)
    return val


def take_reading_with_retry():
    while True:
        try:
            return int(Bridge.call("take_reading"))
        except Exception as e:
            print(f"[ERROR] {e} — re-trigger to retry:", flush=True)
            print(f">>> {TRIGGER_CMD}", flush=True)
            while not os.path.exists(TRIGGER):
                time.sleep(0.5)
            os.remove(TRIGGER)


def user_loop():
    s = ctx["state"]

    if s == "await_mcu":
        pass  # on_log transitions to await_known_weight

    elif s == "await_known_weight":
        if os.path.exists(WEIGHT_FILE):
            ctx["known_g"] = read_weight_file()
            print(f"Bowl weight: {ctx['known_g']:.1f}g", flush=True)
            step(f"Scale EMPTY. Trigger when ready: {TRIGGER_CMD}")
            ctx["state"] = "await_tare"

    elif s == "await_tare":
        if os.path.exists(TRIGGER):
            os.remove(TRIGGER)
            print("Taking tare...", flush=True)
            ctx["raw_zero"] = take_reading_with_retry()
            print(f"Tare = {ctx['raw_zero']} raw", flush=True)
            if ctx["raw_zero"] > 0 or ctx["raw_zero"] < -100000:
                print(f"[WARN] Tare = {ctx['raw_zero']} is outside normal range.", flush=True)
                print("[WARN] Expected around -12000 to -14000. Scale not empty?", flush=True)
                ctx["state"] = "await_tare"
                return
            step(f"Place bowl ({ctx['known_g']:.0f}g) on scale. "
                 f"Trigger when settled: {TRIGGER_CMD}")
            ctx["state"] = "await_w1"

    elif s == "await_w1":
        if os.path.exists(TRIGGER):
            os.remove(TRIGGER)
            print("Taking W1...", flush=True)
            raw_w1 = take_reading_with_retry()                          # 1. first read
            span = raw_w1 - ctx["raw_zero"]
            print("Verifying W1 stability...", flush=True)
            raw_w1_v = take_reading_with_retry()                        # 2. second read
            if abs(raw_w1_v - raw_w1) > abs(span) * 0.10:              # 3. stability check
                print(f"[WARN] W1 unstable (r1={raw_w1}, r2={raw_w1_v}). "
                      "Bowl still settling. Re-trigger.", flush=True)
                ctx["state"] = "await_w1"
                return
            ctx["cal_factor"] = span / ctx["known_g"]                   # 4. calculate cal_factor
            EXPECTED_CAL = 103.0
            ratio = ctx["cal_factor"] / EXPECTED_CAL
            if ratio < 0.5 or ratio > 2.0:                             # 5. sanity check
                print(f"[WARN] cal_factor = {ctx['cal_factor']:.1f} is {ratio:.1f}x "
                      f"expected ({EXPECTED_CAL}). Hand on scale or bowl still moving?",
                      flush=True)
                print("[WARN] Re-trigger W1 after fully removing hands.", flush=True)
                ctx["state"] = "await_w1"
                return
            w1_g = ctx["known_g"]                                       # 7. accept
            ctx["readings"].append((raw_w1, w1_g))
            print(f"W1 = {w1_g:.2f}g  (cal = {ctx['cal_factor']:.2f} raw/g)", flush=True)
            step(f"Remove some drops. Trigger when settled: {TRIGGER_CMD}")
            ctx["state"] = "await_w2"

    elif s == "await_w2":
        if os.path.exists(TRIGGER):
            os.remove(TRIGGER)
            print("Taking W2...", flush=True)
            raw_w2 = take_reading_with_retry()
            raw_w2_v = take_reading_with_retry()
            if abs(raw_w2_v - raw_w2) > 2000:
                print("[WARN] Reading unstable. Scale still moving. Re-trigger.", flush=True)
                ctx["state"] = "await_w2"
                return
            raw_w2 = (raw_w2 + raw_w2_v) // 2
            w2_g = (raw_w2 - ctx["raw_zero"]) / ctx["cal_factor"]
            d21 = w2_g - ctx["readings"][-1][1]
            ctx["readings"].append((raw_w2, w2_g))
            print(f"W2 = {w2_g:.2f}g  (delta = {d21:+.2f}g)", flush=True)
            step(f"Remove more drops. Trigger when settled: {TRIGGER_CMD}")
            ctx["state"] = "await_w3"

    elif s == "await_w3":
        if os.path.exists(TRIGGER):
            os.remove(TRIGGER)
            print("Taking W3...", flush=True)
            raw_w3 = take_reading_with_retry()
            raw_w3_v = take_reading_with_retry()
            if abs(raw_w3_v - raw_w3) > 2000:
                print("[WARN] Reading unstable. Scale still moving. Re-trigger.", flush=True)
                ctx["state"] = "await_w3"
                return
            raw_w3 = (raw_w3 + raw_w3_v) // 2
            w3_g = (raw_w3 - ctx["raw_zero"]) / ctx["cal_factor"]
            w1_g = ctx["readings"][0][1]
            w2_g = ctx["readings"][1][1]
            d32 = w3_g - w2_g
            d31 = w3_g - w1_g
            d21 = d31 - d32
            ctx["readings"].append((raw_w3, w3_g))
            print(f"W3 = {w3_g:.2f}g  (delta = {d32:+.2f}g)", flush=True)
            print("=== COMPLETE ===", flush=True)
            print(f"cal_factor = {ctx['cal_factor']:.4f} raw/g", flush=True)
            print(f"W1={w1_g:.2f}g  W2={w2_g:.2f}g  W3={w3_g:.2f}g", flush=True)
            print(f"W2-W1={d21:+.2f}g  W3-W2={d32:+.2f}g  W3-W1={d31:+.2f}g", flush=True)
            results = {
                "known_weight_g": ctx["known_g"],
                "cal_factor": round(ctx["cal_factor"], 4),
                "raw_zero": ctx["raw_zero"],
                "W1_g": round(w1_g, 2),
                "W2_g": round(w2_g, 2),
                "W3_g": round(w3_g, 2),
                "W2_W1_g": round(d21, 2),
                "W3_W2_g": round(d32, 2),
                "W3_W1_g": round(d31, 2),
            }
            with open(RESULTS_PATH, "w") as f:
                json.dump(results, f, indent=2)
            print("Results saved to RESULTS_A.json", flush=True)
            ctx["state"] = "done"

    time.sleep(0.5)


def on_log(data):
    msg = str(data)
    if "MCU ready" in msg:
        if ctx["state"] == "await_mcu":
            ctx["state"] = "await_known_weight"
            step(f"Enter bowl weight (g): {WEIGHT_CMD}")
        return  # suppress all repeated MCU ready prints
    print(msg, flush=True)


Bridge.provide("log", on_log)
App.run(user_loop=user_loop)
