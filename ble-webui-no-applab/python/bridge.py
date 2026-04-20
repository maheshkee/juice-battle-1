import socket, msgpack, threading

SOCK = "/var/run/arduino-router.sock"

class ArduinoBridge:
    def __init__(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.counter = 0
        self.pending = {}
        self.results = {}
        self.lock = threading.Lock()
        self.handlers = {}

    def connect(self):
        self.sock.connect(SOCK)
        threading.Thread(target=self._recv_loop, daemon=True).start()

    def call(self, method, args=[], timeout=5.0):
        with self.lock:
            self.counter += 1
            mid = self.counter
            ev = threading.Event()
            self.pending[mid] = ev
        self._send([0, mid, method, args])
        ev.wait(timeout)
        return self.results.pop(mid, None)

    def notify(self, method, args=[]):
        self._send([2, method, args])

    def on(self, method, fn):
        self.handlers[method] = fn
        with self.lock:
            self.counter += 1
            mid = self.counter
        self._send([0, mid, "$/register", [method]])

    def _send(self, msg):
        self.sock.sendall(msgpack.packb(msg, use_bin_type=True))

    def _recv_loop(self):
        unpacker = msgpack.Unpacker(raw=False)
        while True:
            try:
                data = self.sock.recv(4096)
                if not data:
                    break
                unpacker.feed(data)
                for msg in unpacker:
                    self._dispatch(msg)
            except Exception as e:
                print("[bridge] error: " + str(e))
                break

    def _dispatch(self, msg):
        if msg[0] == 1:
            mid = msg[1]
            with self.lock:
                ev = self.pending.pop(mid, None)
            if ev:
                self.results[mid] = msg[3]
                ev.set()
        elif msg[0] == 2:
            fn = self.handlers.get(msg[1])
            if fn:
                try:
                    fn(msg[2])
                except Exception as e:
                    print("[bridge] handler error: " + str(e))
