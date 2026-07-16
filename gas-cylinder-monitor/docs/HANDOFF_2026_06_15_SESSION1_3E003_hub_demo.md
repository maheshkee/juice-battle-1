# Session Handoff — 2026-06-15 Session 1
# 3E-003 BLE transport + hub deployment + demo

## Session goal
Build end-to-end BLE transport and deploy hub App Lab app.
Demo: boss places weight → grams appear on WebUI.

## Gate result
PASSED. Demo achieved 2026-06-15.

## What was built
- node/3E003_ble_transport_v1/3E003_ble_transport_v1.ino
- hub/app.yaml, setup.sh, deploy.sh
- hub/python/main.py, hub/python/ble_subscriber.py
- hub/assets/index.html, hub/assets/socket.io.min.js

## Key rules added this session
- Never RemoveDevice before Connect on fresh BLE discovery (BlueZ QRB2210)
- deploy.sh must always restart socat service before app start
- requirements.txt must list /app/wheels/ file paths, not package names
- setup.sh must build wheels from source (libdbus-1-dev required)
- APP_NAME derived from app.yaml name: field, not basename of folder

## Next session
1. Accuracy investigation — place known weights, record actual vs measured
2. Timestamps — millis-based on node, wall clock on hub
3. Unified log file
4. Modular refactor of production node sketch

---
