import os

_APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Gas monitor
REFILL_THRESHOLD_KG    = 8.0
PREDICTION_WINDOW_DAYS = 7
SENSOR_SAMPLE_COUNT    = 20

GAS_DB_PATH = os.path.join(_APP_DIR, "data", "gas_monitor.db")
