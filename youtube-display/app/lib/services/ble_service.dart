import 'dart:async';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ─── UUIDs ────────────────────────────────────────────────────────────────────
// Service:  a01c0000-0000-0000-0000-000000000000
// CMD char: a01c0001-0000-0000-0000-000000000000  (WRITE)
// EVT char: a01c0002-0000-0000-0000-000000000000  (NOTIFY) — BT audio events
// ─────────────────────────────────────────────────────────────────────────────

class BleUuids {
  static final service = Guid('a01c0000-0000-0000-0000-000000000000');
  static final url     = Guid('a01c0001-0000-0000-0000-000000000000');
  static final evt     = Guid('a01c0002-0000-0000-0000-000000000000');
}

enum ConnState { disconnected, scanning, connecting, connected }

// BT device model
class BtDevice {
  final String mac;
  final String name;
  final int    rssi;
  BtDevice({required this.mac, required this.name, this.rssi = 0});
  factory BtDevice.fromJson(Map<String, dynamic> j) => BtDevice(
    mac:  j['mac']  ?? '',
    name: j['name'] ?? '',
    rssi: j['rssi'] ?? 0,
  );
}

class BleService {
  BluetoothDevice?         _device;
  BluetoothCharacteristic? _urlChar;
  StreamSubscription?      _scanSub;
  StreamSubscription?      _connSub;

  final _connState     = StreamController<ConnState>.broadcast();
  final _devName       = StreamController<String>.broadcast();
  final _logs          = StreamController<String>.broadcast();
  final _btScanResults = StreamController<List<BtDevice>>.broadcast();
  final _btTrusted     = StreamController<List<BtDevice>>.broadcast();
  final _btScanning    = StreamController<bool>.broadcast();
  final _btConnected   = StreamController<BtDevice>.broadcast();
  final _btDisconnected= StreamController<String>.broadcast();
  final _btError       = StreamController<String>.broadcast();

  Stream<ConnState>    get connState      => _connState.stream;
  Stream<String>       get devName        => _devName.stream;
  Stream<String>       get logs           => _logs.stream;
  Stream<List<BtDevice>> get btScanResults => _btScanResults.stream;
  Stream<List<BtDevice>> get btTrusted     => _btTrusted.stream;
  Stream<bool>         get btScanning     => _btScanning.stream;
  Stream<BtDevice>     get btConnected    => _btConnected.stream;
  Stream<String>       get btDisconnected => _btDisconnected.stream;
  Stream<String>       get btError        => _btError.stream;

  ConnState _state = ConnState.disconnected;
  ConnState get state => _state;

  // v2.1 pairing hook
  // ignore: unused_field
  String? _pairedBoardId;

  void _log(String m) => _logs.add(m);
  void _setState(ConnState s) { _state = s; _connState.add(s); }

  // ── Scan ──────────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    if (_state == ConnState.scanning) return;
    final scanPerm    = await Permission.bluetoothScan.status;
    final connectPerm = await Permission.bluetoothConnect.status;
    if (!scanPerm.isGranted || !connectPerm.isGranted) {
      _log('[SCAN] Bluetooth permission not granted');
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
            ? r.device.platformName : 'Board';
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
              _log('[BLE] CMD characteristic ready');
            } else if (c.uuid == BleUuids.evt) {
              await c.setNotifyValue(true);
              c.onValueReceived.listen(_handleEvt);
              _log('[BLE] EVT notify subscribed');
            }
          }
        }
      }

      if (_urlChar == null) {
        _log('[ERROR] CMD characteristic not found on board');
        _setState(ConnState.disconnected);
        return;
      }

      _devName.add(device.platformName.isNotEmpty
          ? device.platformName : 'AQ2');
      _setState(ConnState.connected);
      _log('[BLE] Connected to board');

    } catch (e) {
      _log('[ERROR] $e');
      _setState(ConnState.disconnected);
    }
  }

  // ── EVT handler — parses JSON events from board ───────────────────────────

  void _handleEvt(List<int> value) {
    try {
      final json = jsonDecode(utf8.decode(value)) as Map<String, dynamic>;
      final event = json['event'] as String? ?? '';

      switch (event) {
        case 'bt_scan_results':
          final devices = (json['devices'] as List? ?? [])
              .map((d) => BtDevice.fromJson(d as Map<String, dynamic>))
              .toList();
          _btScanResults.add(devices);
          break;

        case 'bt_scan_status':
          _btScanning.add(json['scanning'] as bool? ?? false);
          break;

        case 'bt_trusted':
          final devices = (json['devices'] as List? ?? [])
              .map((d) => BtDevice.fromJson(d as Map<String, dynamic>))
              .toList();
          _btTrusted.add(devices);
          break;

        case 'bt_connected':
          _btConnected.add(BtDevice(
            mac:  json['mac']  ?? '',
            name: json['name'] ?? '',
          ));
          // Refresh trusted list
          _write('CMD:BT_LIST');
          break;

        case 'bt_disconnected':
          _btDisconnected.add(json['mac'] as String? ?? '');
          _write('CMD:BT_LIST');
          break;

        case 'bt_error':
          final msg = json['message'] as String? ?? 'Unknown error';
          _btError.add(msg);
          _log('[BT ERROR] $msg');
          break;
      }
    } catch (e) {
      _log('[EVT] Parse error: $e');
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
    if (_urlChar == null) { _log('[ERROR] Not connected'); return; }
    try {
      await _urlChar!.write(utf8.encode(cmd), withoutResponse: true);
      _log('[SEND] $cmd');
    } catch (e) {
      _log('[ERROR] Write failed: $e');
    }
  }

  // ── Player commands ───────────────────────────────────────────────────────

  Future<void> sendUrl(String url)  => _write(url);
  Future<void> playerPause()        => _write('CMD:PAUSE');
  Future<void> playerResume()       => _write('CMD:RESUME');
  Future<void> playerStop()         => _write('CMD:STOP');
  Future<void> playerVolUp()        => _write('CMD:VOL_UP');
  Future<void> playerVolDown()      => _write('CMD:VOL_DOWN');

  // ── BT audio management commands ─────────────────────────────────────────

  Future<void> btScanStart()            => _write('CMD:BT_SCAN_START');
  Future<void> btScanStop()             => _write('CMD:BT_SCAN_STOP');
  Future<void> btList()                 => _write('CMD:BT_LIST');
  Future<void> btPair(String mac)       => _write('CMD:BT_PAIR:$mac');
  Future<void> btConnect(String mac)    => _write('CMD:BT_CONNECT:$mac');
  Future<void> btDisconnect(String mac) => _write('CMD:BT_DISCONNECT:$mac');
  Future<void> btForget(String mac)     => _write('CMD:BT_FORGET:$mac');

  // ── Cleanup ───────────────────────────────────────────────────────────────

  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _connState.close();
    _devName.close();
    _logs.close();
    _btScanResults.close();
    _btTrusted.close();
    _btScanning.close();
    _btConnected.close();
    _btDisconnected.close();
    _btError.close();
  }
}
