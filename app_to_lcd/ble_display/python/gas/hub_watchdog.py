import os
import time
import subprocess
import threading

from gas import hub_logger

_BASE_DIR        = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
_DATA_DIR        = os.path.join(_BASE_DIR, 'gas_data')
_RESTART_TRIGGER = os.path.join(_DATA_DIR, 'restart.trigger')
_REBOOT_TRIGGER  = os.path.join(_DATA_DIR, 'reboot.trigger')

CHECK_INTERVAL_S      = 60
READING_STALE_S       = 1800
CONSECUTIVE_FAIL_GATE = 2
POST_ACTION_WAIT_S    = 120


class HubWatchdog:
    def __init__(self):
        self._last_reading_ts  = None
        self._consecutive_fail = 0
        self._escalation_level = 1
        self._lock             = threading.Lock()

    def update_last_reading(self, ts):
        with self._lock:
            self._last_reading_ts = time.time()

    def start(self):
        t = threading.Thread(target=self._run, daemon=True)
        t.start()
        hub_logger.log_watchdog('WATCHDOG_START', interval_s=CHECK_INTERVAL_S)

    def _check_hci0(self):
        try:
            result = subprocess.run(
                ['hciconfig', 'hci0'], capture_output=True, text=True, timeout=5
            )
            return 'UP RUNNING' in result.stdout
        except Exception:
            return False

    def _check_reading_fresh(self):
        with self._lock:
            ts = self._last_reading_ts
        if ts is None:
            return True  # startup grace — no reading received yet
        return (time.time() - ts) < READING_STALE_S

    def _health_ok(self):
        hci0_up = self._check_hci0()
        fresh   = self._check_reading_fresh()
        hub_logger.log_watchdog('HEALTH_CHECK', hci0_up=hci0_up, reading_fresh=fresh)
        # hci0_up is always False inside Docker — hciconfig not available in container.
        # reading_fresh is the correct health signal from inside Docker.
        # Threshold is 1800s (30min) to survive normal 3-4min BLE dropouts.
        return fresh

    def _do_level1(self):
        hub_logger.log_watchdog('LEVEL1_RESET')
        try:
            subprocess.run(['bluetoothctl', 'power', 'off'], timeout=10)
            time.sleep(3)
            subprocess.run(['bluetoothctl', 'power', 'on'], timeout=10)
        except Exception as e:
            hub_logger.log_watchdog('LEVEL1_RESET_ERROR', error=str(e))

    def _do_level2(self):
        hub_logger.log_watchdog('LEVEL2_RESTART_TRIGGERED')
        try:
            os.makedirs(_DATA_DIR, exist_ok=True)
            with open(_RESTART_TRIGGER, 'w') as f:
                f.write('restart\n')
        except Exception as e:
            hub_logger.log_watchdog('LEVEL2_WRITE_ERROR', error=str(e))

    def _do_level3(self):
        hub_logger.log_watchdog('LEVEL3_REBOOT_TRIGGERED')
        try:
            os.makedirs(_DATA_DIR, exist_ok=True)
            with open(_REBOOT_TRIGGER, 'w') as f:
                f.write('reboot\n')
        except Exception as e:
            hub_logger.log_watchdog('LEVEL3_WRITE_ERROR', error=str(e))

    def _run(self):
        while True:
            time.sleep(CHECK_INTERVAL_S)
            if self._health_ok():
                self._consecutive_fail = 0
                self._escalation_level = 1  # reset escalation ladder on recovery
                continue
            self._consecutive_fail += 1
            hub_logger.log_watchdog('HEALTH_FAIL', consecutive=self._consecutive_fail)
            if self._consecutive_fail < CONSECUTIVE_FAIL_GATE:
                continue
            self._consecutive_fail = 0
            level = self._escalation_level
            if level == 1:
                self._do_level1()
                self._escalation_level = 2
            elif level == 2:
                self._do_level2()
                self._escalation_level = 3
            else:
                self._do_level3()
                self._escalation_level = 1  # reset after reboot trigger — system should reboot
            time.sleep(POST_ACTION_WAIT_S)
