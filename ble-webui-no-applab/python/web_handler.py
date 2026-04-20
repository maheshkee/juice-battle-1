import os, json, queue
from flask import Flask, Response, send_from_directory

ASSETS=os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","assets")
app=Flask(__name__)
_state=None

def init(state):
    global _state; _state=state

@app.route("/")
def index(): return send_from_directory(ASSETS,"index.html")

@app.route("/<path:fname>")
def static_file(fname): return send_from_directory(ASSETS,fname)

@app.route("/state")
def get_state():
    return json.dumps(_state.snapshot()),200,{"Content-Type":"application/json"}

@app.route("/events")
def sse():
    q=queue.Queue(); _state.add_sse_queue(q)
    def stream():
        try:
            yield "data: "+json.dumps({"type":"snapshot",**_state.snapshot()})+"\n\n"
            while True:
                try: yield "data: "+q.get(timeout=30)+"\n\n"
                except queue.Empty: yield ": keep-alive\n\n"
        finally: _state.remove_sse_queue(q)
    return Response(stream(),mimetype="text/event-stream",
        headers={"Cache-Control":"no-cache","X-Accel-Buffering":"no"})

def run(host="0.0.0.0",port=5000):
    app.run(host=host,port=port,threaded=True,use_reloader=False)
