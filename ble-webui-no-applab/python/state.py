import threading, time, json, queue

class AppState:
    def __init__(self):
        self._lock = threading.Lock()
        self.led_on = False
        self.ble_connected = False
        self.ble_device = ""
        self.events = []
        self._sse_queues = []

    def update_led(self, state, source="system"):
        with self._lock:
            self.led_on = state
        self._push({"type":"led","state":state,"source":source,"ts":time.strftime("%H:%M:%S")})

    def update_ble(self, connected, device=""):
        with self._lock:
            self.ble_connected = connected
            self.ble_device = device
        self._push({"type":"ble","connected":connected,"device":device,"ts":time.strftime("%H:%M:%S")})

    def add_event(self, etype, data):
        event = {"type":etype,"ts":time.strftime("%H:%M:%S")}
        event.update(data)
        self._push(event)

    def snapshot(self):
        with self._lock:
            return {"led_on":self.led_on,"ble_connected":self.ble_connected,
                    "ble_device":self.ble_device,"events":list(self.events[-30:])}

    def add_sse_queue(self, q):
        with self._lock:
            self._sse_queues.append(q)

    def remove_sse_queue(self, q):
        with self._lock:
            if q in self._sse_queues:
                self._sse_queues.remove(q)

    def _push(self, event):
        with self._lock:
            self.events.append(event)
            if len(self.events) > 200:
                self.events = self.events[-200:]
            qs = list(self._sse_queues)
        data = json.dumps(event)
        for q in qs:
            try:
                q.put_nowait(data)
            except Exception:
                pass
