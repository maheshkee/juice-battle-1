#!/usr/bin/env python3
"""
run.py - Single entry point for BLE WebUI No AppLab

Workflow:
    1. Compile MCU sketch
    2. Verify compile passed  (exit if not)
    3. Auto-detect board IP
    4. Upload sketch to MCU   (exit if not)
    5. Wait for MCU reboot
    6. Start the application
"""

import subprocess
import sys
import os
import time

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
    for line in result.stdout.splitlines():
        if 'network' in line and 'unoq' in line:
            return line.split()[0]
    return None

def upload_sketch():
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
        SKETCH_DIR
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print("\n--- Upload output ---")
        print(result.stderr)
        print("--------------------")
        fail("Upload failed. Check board connection.")

    ok("Sketch uploaded successfully")

    step("Waiting for MCU to reboot (4 seconds)...")
    time.sleep(4)
    ok("MCU ready")

def start_app():
    step("Starting BLE WebUI application...")
    print("")
    sys.path.insert(0, PYTHON_DIR)
    import main
    main.main()

if __name__ == '__main__':
    banner("BLE WebUI No AppLab - Starting Up")
    compile_sketch()
    upload_sketch()
    start_app()
