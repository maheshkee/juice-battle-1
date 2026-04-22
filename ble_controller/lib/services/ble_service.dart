import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/board_event.dart';

class BleUuids {
  static final service = Guid('a00b0000-0000-0000-0000-000000000000');
  static final cmd     = Guid('a00b0002-0000-0000-0000-000000000000');
  static final evt     = Guid('a00b0003-0000-0000-0000-000000000000');
}

enum ConnState { disconnected, scanning, connecting, connected }

class BleService {
  BluetoothDevice?         _device;
  BluetoothCharacteristic? _cmdChar;
  StreamSubscription?      _scanSub;
  StreamSubscription?      _connSub;

  final _connState = StreamController<ConnState>.broadcast();
  final _devName   = StreamController<String>.broadcast();
  final _logs      = StreamController<String>.broadcast();
  final _events    = StreamController<BoardEvent>.broadcast();

  Stream<ConnState>  get connState => _connState.stream;
  Stream<String>     get devName   => _devName.stream;
  Stream<String>     get logs      => _logs.stream;
  Stream<BoardEvent> get events    => _events.stream;

  ConnState _state = ConnState.disconnected;
  ConnState get state => _state;

  void _log(String m) => _logs.add(m);
  void _setState(ConnState s) { _state = s; _connState.add(s); }

  Future<void> startScan() async {
    if (_state == ConnState.scanning) return;
    _setState(ConnState.scanning);
    _log('[SCAN] Looking for BLE-Hub...');
    await FlutterBluePlus.startScan(
      withServices: [BleUuids.service],
      timeout: const Duration(seconds: 15),
    );
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (var r in results) {
        _log('[SCAN] Found: ${r.device.platformName}');
        FlutterBluePlus.stopScan();
        _scanSub?.cancel();
        _connect(r.device);
        return;
      }
    });
    FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && _state == ConnState.scanning) {
        _setState(ConnState.disconnected);
        _log('[SCAN] No device found');
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

  Future<void> _connect(BluetoothDevice device) async {
    _setState(ConnState.connecting);
    _log('[BLE] Connecting to ${device.platformName}...');
    _device = device;
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _log('[BLE] Disconnected from board');
          _setState(ConnState.disconnected);
          _cmdChar = null;
        }
      });
      _log('[BLE] Discovering services...');
      final services = await device.discoverServices();
      for (var svc in services) {
        if (svc.uuid == BleUuids.service) {
          for (var c in svc.characteristics) {
            if (c.uuid == BleUuids.cmd) {
              _cmdChar = c;
              _log('[CHAR] Command char ready');
            } else if (c.uuid == BleUuids.evt) {
              await c.setNotifyValue(true);
              c.onValueReceived.listen((value) => _events.add(BoardEvent.fromBytes(value)));
              _log('[NOTIFY] Subscribed to board events');
            }
          }
        }
      }
      _devName.add(device.platformName);
      _setState(ConnState.connected);
      _log('[BLE] Connected to ${device.platformName}');
      await _write('CMD:GET_STATUS');
    } catch (e) {
      _log('[ERROR] $e');
      _setState(ConnState.disconnected);
    }
  }

  Future<void> disconnect() async {
    _connSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _setState(ConnState.disconnected);
    _log('[BLE] Disconnected');
  }

  Future<void> _write(String cmd) async {
    if (_cmdChar == null) { _log('[ERROR] Not connected'); return; }
    try {
      await _cmdChar!.write(utf8.encode(cmd), withoutResponse: true);
      _log('[SEND] $cmd');
    } catch (e) { _log('[ERROR] Write: $e'); }
  }

  Future<void> sendUrl(String url)          => _write('YT:$url');
  Future<void> sendLedToggle()              => _write('CMD:LED_TOGGLE');
  Future<void> sendLedOn()                  => _write('CMD:LED_ON');
  Future<void> sendLedOff()                 => _write('CMD:LED_OFF');
  Future<void> setModeIdle()                => _write('CMD:MODE_IDLE');
  Future<void> setModeYouTube()             => _write('CMD:MODE_YOUTUBE');
  Future<void> setModeClock()               => _write('CMD:MODE_CLOCK');
  Future<void> playerPause()                => _write('CMD:PLAYER_PAUSE');
  Future<void> playerResume()               => _write('CMD:PLAYER_RESUME');
  Future<void> playerStop()                 => _write('CMD:PLAYER_STOP');
  Future<void> playerMute()                 => _write('CMD:PLAYER_MUTE');
  Future<void> playerUnmute()               => _write('CMD:PLAYER_UNMUTE');
  Future<void> scanStart()                  => _write('CMD:SCAN_START');
  Future<void> scanStop()                   => _write('CMD:SCAN_STOP');
  Future<void> connectDevice(String mac)    => _write('CMD:CONNECT:$mac');
  Future<void> disconnectDevice(String mac) => _write('CMD:DISCONNECT:$mac');
  Future<void> forgetDevice(String mac)     => _write('CMD:FORGET:$mac');
  Future<void> getStatus()                  => _write('CMD:GET_STATUS');

  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _connState.close();
    _devName.close();
    _logs.close();
    _events.close();
  }
}
