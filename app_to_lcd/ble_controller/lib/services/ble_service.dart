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
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (var r in results) {
        if (r.device.platformName == 'BLE-Hub') {
          _log('[SCAN] Found: ${r.device.platformName}');
          FlutterBluePlus.stopScan();
          _scanSub?.cancel();
          _connect(r.device);
          return;
        }
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
              c.onValueReceived.listen((value) {
                final evt = BoardEvent.tryFromBytes(value);
                if (evt != null && evt.event != 'unknown') {
                  _events.add(evt);
                }
              });
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

  Future<void> sendUrl(String url)                        => _write('YT:$url');
  Future<void> sendUrlWithTitle(String url, String title) => _write('YT:$url||$title');
  Future<void> sendLedToggle()                            => _write('CMD:LED_TOGGLE');
  Future<void> sendLedOn()                                => _write('CMD:LED_ON');
  Future<void> sendLedOff()                               => _write('CMD:LED_OFF');
  Future<void> setModeIdle()                              => _write('CMD:MODE_IDLE');
  Future<void> setModeYouTube()                           => _write('CMD:MODE_YOUTUBE');
  Future<void> setModeClock()                             => _write('CMD:MODE_CLOCK');
  Future<void> playerPause()                              => _write('CMD:PLAYER_PAUSE');
  Future<void> playerResume()                             => _write('CMD:PLAYER_RESUME');
  Future<void> playerStop()                               => _write('CMD:PLAYER_STOP');
  Future<void> playerMute()                               => _write('CMD:PLAYER_MUTE');
  Future<void> playerUnmute()                             => _write('CMD:PLAYER_UNMUTE');
  Future<void> playerVolUp()                              => _write('CMD:PLAYER_VOL_UP');
  Future<void> playerVolDown()                            => _write('CMD:PLAYER_VOL_DOWN');
  Future<void> playerSeekForward()                        => _write('CMD:PLAYER_SEEK_FWD');
  Future<void> playerSeekBack()                           => _write('CMD:PLAYER_SEEK_BACK');
  Future<void> playerReplay()                             => _write('CMD:PLAYER_REPLAY');
  Future<void> playerQuality(String q)                    => _write('CMD:PLAYER_QUALITY:$q');
  Future<void> scanStart()                                => _write('CMD:SCAN_START');
  Future<void> scanStop()                                 => _write('CMD:SCAN_STOP');
  Future<void> connectDevice(String mac)                  => _write('CMD:CONNECT:$mac');
  Future<void> disconnectDevice(String mac)               => _write('CMD:DISCONNECT:$mac');
  Future<void> forgetDevice(String mac)                   => _write('CMD:FORGET:$mac');
  Future<void> getStatus()                                => _write('CMD:GET_STATUS');
  Future<void> queuePlay()                                => _write('CMD:QUEUE_PLAY');
  Future<void> queuePause()                               => _write('CMD:QUEUE_PAUSE');
  Future<void> queueResume()                              => _write('CMD:QUEUE_RESUME');
  Future<void> queueSkip()                                => _write('CMD:QUEUE_SKIP');
  Future<void> queueReplay()                              => _write('CMD:QUEUE_REPLAY');
  Future<void> queueStop()                                => _write('CMD:QUEUE_STOP');
  Future<void> queueGoto(int index)                       => _write('CMD:QUEUE_GOTO:$index');
  Future<void> watchLaterGet()                            => _write('CMD:WATCHLATER_GET');
  Future<void> btScanStart()                              => _write('CMD:BT_SCAN_START');
  Future<void> btScanStop()                               => _write('CMD:BT_SCAN_STOP');
  Future<void> btPair(String mac)                         => _write('CMD:BT_PAIR:$mac');
  Future<void> btConnect(String mac)                      => _write('CMD:BT_CONNECT:$mac');
  Future<void> btDisconnect(String mac)                   => _write('CMD:BT_DISCONNECT:$mac');
  Future<void> btForget(String mac)                       => _write('CMD:BT_FORGET:$mac');
  Future<void> btStatus()                                 => _write('CMD:BT_STATUS');
  Future<void> btList()                                   => _write('CMD:BT_LIST');
  Future<void> btGetConnected()                           => _write('CMD:BT_GET_CONNECTED');
  Future<void> historyClear()                             => _write('CMD:HISTORY_CLEAR');
  Future<void> watchLaterRemove(String url)               => _write('WATCHLATER_REMOVE:$url');
  Future<void> watchLaterAdd(String url, String title, String videoId) =>
      _write('WATCHLATER_ADD:$url||$title||$videoId');

  Future<void> sendQueue(List<QueueItem> items) async {
    final payload = jsonEncode(items.map((e) => e.toJson()).toList());
    await _write('QUEUE:$payload');
  }

  Future<void> sendSchedule(List<ScheduleEntry> entries) async {
    final payload = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _write('SCHEDULE:$payload');
  }

  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _connState.close();
    _devName.close();
    _logs.close();
    _events.close();
  }
}
