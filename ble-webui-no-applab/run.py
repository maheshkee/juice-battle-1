#!/usr/bin/env python3
"""
run.py - Single entry point for BLE WebUI No AppLab

Workflow:
    1. Compile MCU sketch
    2. Verify compile passed  (exit if not)
    3. Prompt for board password (used for network upload auth)
    4. Auto-detect board IP
    5. Upload sketch to MCU   (exit if not)
    6. Wait for MCU reboot
    7. Start the application
"""

import subprocess
import sys
import os
import time
import getpass

ROOT       = os.path.dirname(os.path.abspath(__file__))
SKETCH_DIR = os.path.join(ROOT, 'sketch')
PYTHON_DIR = os.path.join(ROOT, 'python')
FQBN       = 'arduino:zephyr:unoq'
INTERNAL   = os.path.expanduser('~/.arduino15/internal')

LIBRARIES = [
    'Arduino_RouterBridge_0.4.1_d378119a47d2c8c4/Arduino_RouterBridge',
    'Arduino_RPClite_0.2.1_ce72ff552a496aef/Arduino_RPClite',
    'MsgPack_0.4.2_a0d4adc5044d022c/MsgPack',
    'DebugLog_0.8.4_c199e2cf6415ecc8/DebugLog',
    'ArxContainer_0.7.0_007f0bb2a1cdefe3/ArxContainer',
    'ArxTypeTraits_0.3.2_d65e2aabfeed7838/ArxTypeTraits',
]

def banner(msg):
    print("")
    print("=" * 52)
    print("  " + msg)
    print("=" * 52)

def step(msg):
    print("\n[>] " + msg)

def ok(msg):
    print("    [OK]   " + msg)

def fail(msg):
    print("    [FAIL] " + msg)
    print("\nAborting. Fix the error above and try again.")
    sys.exit(1)

def info(msg):
    print("    [..]   " + msg)

def compile_sketch():
    step("Compiling MCU sketch...")

    cmd = ['arduino-cli', 'compile', '--fqbn', FQBN]
    for lib in LIBRARIES:
        lib_path = os.path.join(INTERNAL, lib)
        if not os.path.isdir(lib_path):
            fail("Library not found: " + lib_path +
                 "\n    Run setup.sh first or check library paths.")
        cmd += ['--library', lib_path]
    cmd.append(SKETCH_DIR)

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print("\n--- Compiler output ---")
        print(result.stderr)
        print("-----------------------")
        fail("Compilation failed. Sketch NOT uploaded.")

    for line in result.stdout.splitlines():
        if 'Sketch uses' in line or 'Global variables' in line:
            info(line.strip())

    ok("Sketch compiled successfully")

def get_board_ip():
    result = subprocess.run(
        ['arduino-cli', 'board', 'list'],
        capture_output=True, text=True
    )
    ipv4 = None
    ipv6 = None
    for line in result.stdout.splitlines():
        if 'network' in line and 'unoq' in line:
            ip = line.split()[0]
            # Prefer IPv4 (contains dots, no colons)
            if '.' in ip and ':' not in ip:
                ipv4 = ip
            elif ':' in ip:
                ipv6 = ip
    return ipv4 or ipv6 or None

def wait_for_router():
    """Wait until arduino-router is active before attempting upload."""
    info("Checking arduino-router is ready...")
    for i in range(10):
        r = subprocess.run(
            ['systemctl', 'is-active', 'arduino-router'],
            capture_output=True, text=True)
        if r.stdout.strip() == 'active':
            ok("arduino-router is active")
            time.sleep(2)  # extra settle time after active
            return
        info("Waiting for arduino-router... (" + str(i+1) + "/10)")
        time.sleep(2)
    fail("arduino-router did not become active. Run: sudo systemctl start arduino-router")

def upload_sketch(password):
    wait_for_router()

    step("Detecting board on network...")
    ip = get_board_ip()
    if not ip:
        fail("Board not found on network.\n"
             "    Check: arduino-cli board list\n"
             "    Check: systemctl status arduino-router")
    ok("Board found at " + ip)

    step("Uploading sketch to MCU via " + ip + "...")
    cmd = [
        'arduino-cli', 'upload',
        '--port', ip,
        '--protocol', 'network',
        '--fqbn', FQBN,
        '--upload-field', 'password=' + password,
        SKETCH_DIR
    ]

    # Retry up to 3 times - router may still be settling
    for attempt in range(1, 4):
        result = subprocess.run(cmd)
        if result.returncode == 0:
            break
        if attempt < 3:
            info("Upload attempt " + str(attempt) + " failed, retrying in 4s...")
            time.sleep(8)
        else:
            fail("Upload failed after 3 attempts. Check board connection or password.")

    ok("Sketch uploaded successfully")

    step("Waiting for MCU to reboot and bridge to re-establish (8 seconds)...")
    time.sleep(8)
    ok("MCU ready")

def start_app():
    step("Starting BLE WebUI application...")
    print("")
    main_path = os.path.join(PYTHON_DIR, 'main.py')
    # Replace current process entirely with python3 main.py
    # This avoids GLib/Flask threading conflicts from import context
    os.execv(sys.executable, [sys.executable, main_path])

if __name__ == '__main__':
    banner("BLE WebUI No AppLab - Starting Up")
    compile_sketch()
    board_password = getpass.getpass("  Board password (default: arduino): ")
    upload_sketch(board_password)
    start_app()
