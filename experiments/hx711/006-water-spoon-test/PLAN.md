# PLAN.md — 006-water-spoon-test

**Question**: Can the HX711 + load cell system reliably detect small unknown weight changes (a few drops of water removed from a bowl)?

---

## Part A — Today

Three prompted readings with drops removed between each. No known weight — just "some drops". Establishes whether the deltas are detectable and consistent.

### Physical Setup
- Bowl of water on the load cell platform
- Bowl stays on scale for the entire experiment — never removed
- User removes drops by hand between readings
- Hands fully off scale before triggering each reading

### Sequence

| Step | Action | Expected |
|------|--------|----------|
| W1 | Bowl placed, trigger pressed | Baseline raw average |
| W2 | Some drops removed, trigger pressed | Lower than W1 |
| W3 | More drops removed, trigger pressed | Lower than W2 |

### How Readings Are Taken
- MCU registers `take_reading` handler via `Bridge.provide_safe()`
- Python poll_loop watches `~/trigger.txt`
- User runs `touch ~/trigger.txt` in a second terminal to trigger each reading
- MCU takes 20 consecutive raw samples at 100 ms intervals (~2 s total)
- MCU returns the average of 20 samples
- Python logs the value and deltas

### Output
- Real-time log via `arduino-app-cli app logs user:hx711-006-water-spoon-a --follow`
- Machine-readable results written to `RESULTS_A.json` in this folder

---

## Part B — Later

TBD. Likely: repeat with known weights to calibrate the delta in raw units → grams.

---

## App

- **APP_NAME**: `hx711-006-water-spoon-a`
- **App path**: `~/ArduinoApps/experiments/hx711/006-water-spoon-test/app/`
- **Symlink**: `~/ArduinoApps/hx711-006-water-spoon-a`
- **Deploy**: `cd app/ && bash deploy.sh`
