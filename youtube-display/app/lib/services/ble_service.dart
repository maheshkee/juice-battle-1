import 'dart:async';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ─── UUIDs ────────────────────────────────────────────────────────────────────
// Service:  a01c0000-0000-0000-0000-000000000000
// URL char: a01c0001-0000-0000-0000-000000000000  (WRITE)
//
// v2.1 pairing note:
//   _pairedBoardId is reserved for the exclusive-pairing token from QR scan.
//   _write() has a hook comment where the token header will be prepended.
//   BoardIdentity model will be added in v2.1 — no structural changes needed.
// ─────────────────────────────────────────────────────────────────────────────

class BleUuids {
  static final service = Guid('a01c0000-0000-0000-0000-000000000000');
  static final url     = Guid('a01c0001-0000-0000-0000-000000000000');
}

enum ConnState { disconnected, scanning, connecting, connected }

class BleService {
  BluetoothDevice?         _device;
  BluetoothCharacteristic? _urlChar;
  StreamSubscription?      _scanSub;
  StreamSubscription?      _connSub;

  final _connState = StreamController<ConnState>.broadcast();
  final _devName   = StreamController<String>.broadcast();
  final _logs      = StreamController<String>.broadcast();

  Stream<ConnState> get connState => _connState.stream;
  Stream<String>    get devName   => _devName.stream;
  Stream<String>    get logs      => _logs.stream;

  ConnState _state = ConnState.disconnected;
  ConnState get state => _state;

  // v2.1 pairing hook — holds token once QR pairing is implemented
  // ignore: unused_field
  String? _pairedBoardId;

  void _log(String m) => _logs.add(m);
  void _setState(ConnState s) {
    _state = s;
    _connState.add(s);
  }

  // ── Scan ──────────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    if (_state == ConnState.scanning) return;
    final scanPerm    = await Permission.bluetoothScan.status;
    final connectPerm = await Permission.bluetoothConnect.status;
    if (!scanPerm.isGranted || !connectPerm.isGranted) {
      _log('[SCAN] Bluetooth permission not granted — check app settings');
      return;
    }
    _setState(ConnState.scanning);
    _log('[SCAN] Searching for YouTube Display board...');


    await FlutterBluePlus.startScan(
      withServices: [BleUuids.service],
      timeout: const Duration(seconds: 15),
    );

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (var r in results) {
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : 'Board';
        _log('[SCAN] Found: $name');
        FlutterBluePlus.stopScan();
        _scanSub?.cancel();
        _connect(r.device);
        return;
      }
    });

    FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && _state == ConnState.scanning) {
        _setState(ConnState.disconnected);
        _log('[SCAN] Board not found — is it powered on?');
      }
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    if (_state == ConnState.scanning) {
      _setState(ConnState.disconnected);
      _log('[SCAN] Stopped');
    }
  }

  // ── Connect ───────────────────────────────────────────────────────────────

  Future<void> _connect(BluetoothDevice device) async {
    _setState(ConnState.connecting);
    _log('[BLE] Connecting...');
    _device = device;

    try {
      await device.connect(timeout: const Duration(seconds: 10));

      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _log('[BLE] Disconnected from board');
          _setState(ConnState.disconnected);
          _urlChar = null;
        }
      });

      _log('[BLE] Discovering services...');
      final services = await device.discoverServices();

      for (var svc in services) {
        if (svc.uuid == BleUuids.service) {
          for (var c in svc.characteristics) {
            if (c.uuid == BleUuids.url) {
              _urlChar = c;
              _log('[BLE] Characteristic ready');
            }
          }
        }
      }

      if (_urlChar == null) {
        _log('[ERROR] URL characteristic not found on board');
        _setState(ConnState.disconnected);
        return;
      }

      _devName.add(
        device.platformName.isNotEmpty ? device.platformName : 'AQ2',
      );
      _setState(ConnState.connected);
      _log('[BLE] Connected to board');
    } catch (e) {
      _log('[ERROR] $e');
      _setState(ConnState.disconnected);
    }
  }

  Future<void> disconnect() async {
    _connSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _urlChar = null;
    _setState(ConnState.disconnected);
    _log('[BLE] Disconnected');
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> _write(String cmd) async {
    if (_urlChar == null) {
      _log('[ERROR] Not connected');
      return;
    }
    // v2.1 pairing hook:
    // final payload = _pairedBoardId != null ? '$_pairedBoardId:$cmd' : cmd;
    try {
      await _urlChar!.write(utf8.encode(cmd), withoutResponse: true);
      _log('[SEND] $cmd');
    } catch (e) {
      _log('[ERROR] Write failed: $e');
    }
  }

  // ── Commands — must match ble_central.py protocol exactly ─────────────────

  Future<void> sendUrl(String url)  => _write(url);
  Future<void> playerPause()        => _write('CMD:PAUSE');
  Future<void> playerResume()       => _write('CMD:RESUME');
  Future<void> playerStop()         => _write('CMD:STOP');
  Future<void> playerVolUp()        => _write('CMD:VOL_UP');
  Future<void> playerVolDown()      => _write('CMD:VOL_DOWN');

  // ── Cleanup ───────────────────────────────────────────────────────────────

  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _connState.close();
    _devName.close();
    _logs.close();
  }
}
