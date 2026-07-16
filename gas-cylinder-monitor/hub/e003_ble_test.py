import asyncio
import json
import os
from datetime import datetime
from bleak import BleakScanner, BleakClient

CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")


def load_config():
    with open(CONFIG_PATH) as f:
        return json.load(f)


def save_config(config):
    with open(CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)


async def notification_handler(sender, data):
    hub_ts = datetime.now().isoformat(timespec='seconds')
    raw_str = data.decode('utf-8')
    try:
        payload = json.loads(raw_str)
        grams = payload["grams"]
        quality = payload["quality"]
        sigma = payload["sigma"]
        print(f"[{hub_ts}] grams={grams:.1f}g  quality={quality}  sigma={sigma:.2f}g")
    except Exception as e:
        print(f"[{hub_ts}] Parse error: {e}  raw: {raw_str}")


async def connect_and_subscribe(config):
    while True:
        try:
            target = None

            # Phase 1: try cached MAC
            if config.get("device_address"):
                print(f"Scanning (cached MAC: {config['device_address']})...")
                scanner = BleakScanner(service_uuids=[config["service_uuid"]])
                devices = await scanner.discover(timeout=config["scan_timeout_s"])
                target = next(
                    (d for d in devices if d.address.upper() == config["device_address"].upper()),
                    None
                )
                if not target:
                    print("Cached MAC not found. Falling back to UUID discovery...")

            # Phase 2: discover by service UUID + name filter
            if not target:
                print("Scanning by service UUID...")
                scanner = BleakScanner(
                    service_uuids=[config["service_uuid"]]
                )
                devices = await scanner.discover(
                    timeout=config["scan_timeout_s"]
                )

                # bleak on some BlueZ backends ignores service_uuids filter
                # and returns all nearby devices - apply name filter here
                matches = [d for d in devices
                           if d.name == config["device_name"]]

                if len(matches) == 0:
                    print(f"Device '{config['device_name']}' not found.")
                    print(f"Retrying in {config['reconnect_delay_s']}s...")
                    await asyncio.sleep(config["reconnect_delay_s"])
                    continue

                if len(matches) > 1:
                    print(f"WARNING: Multiple '{config['device_name']}' devices found:")
                    for d in matches:
                        print(f"  {d.name}  {d.address}")
                    print("Add device_address to config.json to disambiguate.")
                    await asyncio.sleep(config["reconnect_delay_s"])
                    continue

                # exactly one named match - self-provision
                target = matches[0]
                print(f"Provisioning: discovered {target.name} ({target.address})")
                config["device_address"] = target.address
                save_config(config)
                print(f"MAC cached in config.json: {target.address}")

            print(f"Connecting to {target.name} ({target.address})...")
            async with BleakClient(target.address) as client:
                print("Connected. Subscribing to weight characteristic...")
                await client.start_notify(config["weight_char_uuid"], notification_handler)
                print("Subscribed. Waiting for notifications...")
                print("(Ctrl+C to stop)")
                while client.is_connected:
                    await asyncio.sleep(1.0)
                print("Disconnected.")

        except Exception as e:
            print(f"Error: {e}")

        print(f"Reconnecting in {config['reconnect_delay_s']}s...")
        await asyncio.sleep(config["reconnect_delay_s"])


async def main():
    print("=== E-003 BLE Hub ===")
    config = load_config()
    print(f"Service UUID : {config['service_uuid']}")
    print(f"Cached MAC   : {config.get('device_address') or 'none - will self-provision'}")
    print()
    await connect_and_subscribe(config)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nStopped.")
