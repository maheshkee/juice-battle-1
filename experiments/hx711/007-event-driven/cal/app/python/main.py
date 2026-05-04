import os
import time
from arduino.app_utils import App, Bridge

def on_log(data):
    print(str(data), flush=True)

Bridge.provide("log", on_log)

App.run()
