import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';

class BtAudioDevice {
  final String mac;
  final String name;
  bool paired;
  bool connecting;
  bool connected;

  BtAudioDevice({
    required this.mac,
    required this.name,
    this.paired     = false,
    this.connecting = false,
    this.connected  = false,
  });

  BtAudioDevice copyWith({bool? paired, bool? connecting, bool? connected}) =>
    BtAudioDevice(
      mac:        mac,
      name:       name,
      paired:     paired     ?? this.paired,
      connecting: connecting ?? this.connecting,
      connected:  connected  ?? this.connected,
    );
}

class BtAudioService extends ChangeNotifier {
  final _ble = FlutterBlueClassic();

  bool _scanning = false;
  bool get scanning => _scanning;

  List<BtAudioDevice> _devices = [];
  List<BtAudioDevice> get devices => List.unmodifiable(_devices);

  String? _connectedMac;
  String? _connectedName;
  String? get connectedMac  => _connectedMac;
  String? get connectedName => _connectedName;

  StreamSubscription? _scanSub;
  Timer? _scanTimeout;

  void setPairedDevices(List<Map<String, dynamic>> pairedList) {
    for (final p in pairedList) {
      final mac  = p['mac'] as String? ?? '';
      final name = p['name'] as String? ?? mac;
      if (mac.isEmpty) continue;
      final idx = _devices.indexWhere((d) => d.mac == mac);
      if (idx >= 0) {
        _devices[idx] = _devices[idx].copyWith(paired: true);
      } else {
        _devices = [..._devices, BtAudioDevice(mac: mac, name: name, paired: true)];
      }
    }
    notifyListeners();
  }

  Future<void> startScan() async {
    if (_scanning) return;
    _scanning = true;
    notifyListeners();
    try {
      _ble.startScan();
      _scanSub = _ble.scanResults.listen((result) {
        final mac  = result.address;
        final name = result.name ?? '';
        if (name.isEmpty) return;
        final idx = _devices.indexWhere((d) => d.mac == mac);
        if (idx < 0) {
          _devices = [..._devices, BtAudioDevice(mac: mac, name: name)];
          notifyListeners();
        }
      });
      _scanTimeout = Timer(const Duration(seconds: 15), stopScan);
    } catch (e) {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    _scanTimeout?.cancel();
    _scanSub?.cancel();
    try { _ble.stopScan(); } catch (_) {}
    _scanning = false;
    notifyListeners();
  }

  void clearDevices() {
    _devices = [];
    notifyListeners();
  }

  void setConnecting(String mac, bool value) {
    _devices = _devices.map((d) =>
      d.mac == mac ? d.copyWith(connecting: value) : d).toList();
    notifyListeners();
  }

  void setConnected(String mac, String name) {
    _connectedMac  = mac;
    _connectedName = name;
    _devices = _devices.map((d) =>
      d.mac == mac
        ? d.copyWith(connecting: false, connected: true, paired: true)
        : d.copyWith(connected: false)).toList();
    notifyListeners();
  }

  void setDisconnected() {
    if (_connectedMac != null) {
      _devices = _devices.map((d) =>
        d.mac == _connectedMac
          ? d.copyWith(connecting: false, connected: false)
          : d).toList();
    }
    _connectedMac  = null;
    _connectedName = null;
    notifyListeners();
  }

  void setError(String mac) {
    _devices = _devices.map((d) =>
      d.mac == mac ? d.copyWith(connecting: false, connected: false) : d).toList();
    notifyListeners();
  }

  void setForgotten(String mac) {
    _devices = _devices.where((d) => d.mac != mac).toList();
    notifyListeners();
  }

  @override
  void dispose() {
    stopScan();
    super.dispose();
  }
}
