from arduino.app_utils import App, Logger
from arduino.app_bricks.web_ui import WebUI
import asyncio
from bleak import BleakScanner, BleakClient

logger = Logger("ble-scanner")
ui = WebUI()

discovered_devices = {}

def scan_devices():
    async def _scan():
        devices = await BleakScanner.discover(timeout=5.0)
        for d in devices:
            discovered_devices[d.address] = {
                "name": d.name or "Unknown",
                "address": d.address,
                "rssi": d.rssi
            }
        return list(discovered_devices.values())

    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        devices = loop.run_until_complete(_scan())
        loop.close()
        logger.info(f"Found {len(devices)} devices")
        return {"devices": devices}
    except Exception as e:
        logger.warning(f"Scan error: {e}")
        return {"devices": [], "error": str(e)}

def get_devices():
    return {"devices": list(discovered_devices.values())}

def read_characteristic(payload: dict):
    address = payload.get("address")
    char_uuid = payload.get("char_uuid")
    if not address or not char_uuid:
        return {"error": "address and char_uuid required"}
    async def _read():
        async with BleakClient(address) as client:
            value = await client.read_gatt_char(char_uuid)
            return bytes(value).hex()
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        value = loop.run_until_complete(_read())
        loop.close()
        return {"value": value}
    except Exception as e:
        return {"error": str(e)}

def write_characteristic(payload: dict):
    address = payload.get("address")
    char_uuid = payload.get("char_uuid")
    data = payload.get("data")
    if not address or not char_uuid or not data:
        return {"error": "address, char_uuid and data required"}
    async def _write():
        async with BleakClient(address) as client:
            await client.write_gatt_char(char_uuid, bytes.fromhex(data))
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(_write())
        loop.close()
        return {"ok": True}
    except Exception as e:
        return {"error": str(e)}

ui.expose_api('GET',  '/scan',    scan_devices)
ui.expose_api('GET',  '/devices', get_devices)
ui.expose_api('POST', '/read',    read_characteristic)
ui.expose_api('POST', '/write',   write_characteristic)

App.run()
