from arduino.app_utils import App, Bridge

Bridge.provide("log", lambda data: print(str(data), flush=True))
App.run()
