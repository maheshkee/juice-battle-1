import 'package:flutter/foundation.dart';
import '../models/board_event.dart';

class BoardState extends ChangeNotifier {
  String  mode       = 'idle';
  bool    ledOn      = false;
  bool    scanning   = false;
  String? currentUrl;

  List<ScannedDevice>   scanResults      = [];
  List<ConnectedDevice> connectedDevices = [];
  List<TrustedDevice>   trustedDevices   = [];
  List<HistoryItem>     urlHistory       = [];
  List<String>          logs             = [];

  void addLog(String msg) {
    logs.insert(0, msg);
    if (logs.length > 100) logs.removeLast();
    notifyListeners();
  }

  void applyEvent(BoardEvent evt) {
    final p = evt.payload;
    switch (evt.event) {
      case 'full_status':
        mode       = p['mode']     ?? mode;
        ledOn      = p['led']      ?? ledOn;
        scanning   = p['scanning'] ?? scanning;
        currentUrl = p['current_url'];
        if (p['scan_results'] != null)
          scanResults = (p['scan_results'] as List).map((d) => ScannedDevice.fromJson(d)).toList();
        if (p['connected_devices'] != null)
          connectedDevices = (p['connected_devices'] as List).map((d) => ConnectedDevice.fromJson(d)).toList();
        if (p['trusted'] != null)
          trustedDevices = (p['trusted'] as List).map((d) => TrustedDevice.fromJson(d)).toList();
        if (p['history'] != null)
          urlHistory = (p['history'] as List).map((d) => HistoryItem.fromJson(d)).toList();
        break;
      case 'mode_update':
        mode = p['mode'] ?? mode;
        break;
      case 'led_status':
        ledOn = p['state'] ?? ledOn;
        break;
      case 'scan_status':
        scanning = p['scanning'] ?? scanning;
        break;
      case 'scan_results':
        if (p['devices'] != null) {
          final map = {for (var d in scanResults) d.mac: d};
          for (var d in (p['devices'] as List).map((d) => ScannedDevice.fromJson(d))) {
            if (d.rssi >= -79 || connectedDevices.any((c) => c.mac == d.mac)) map[d.mac] = d;
          }
          scanResults = map.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
        }
        break;
      case 'connected_devices':
        if (p['devices'] != null)
          connectedDevices = (p['devices'] as List).map((d) => ConnectedDevice.fromJson(d)).toList();
        break;
      case 'device_connected':
        final mac = p['mac'] as String? ?? '';
        final name = p['name'] as String? ?? mac;
        if (!connectedDevices.any((d) => d.mac == mac))
          connectedDevices.add(ConnectedDevice(mac: mac, name: name, characteristics: []));
        addLog('[BLE] Connected: $name');
        break;
      case 'device_disconnected':
        connectedDevices.removeWhere((d) => d.mac == (p['mac'] ?? ''));
        addLog('[BLE] Disconnected: ${p['mac']}');
        break;
      case 'device_error':
        addLog('[ERROR] ${p['mac']}: ${p['error']}');
        break;
      case 'trusted_devices':
        if (p['devices'] != null)
          trustedDevices = (p['devices'] as List).map((d) => TrustedDevice.fromJson(d)).toList();
        break;
      case 'characteristic_update':
        final mac  = p['mac']   as String? ?? '';
        final uuid = p['uuid']  as String? ?? '';
        final val  = p['value'] as String? ?? '';
        final name = p['name']  as String? ?? uuid;
        final idx  = connectedDevices.indexWhere((d) => d.mac == mac);
        if (idx >= 0) {
          final chars = List<CharacteristicInfo>.from(connectedDevices[idx].characteristics);
          final ci    = chars.indexWhere((c) => c.uuid == uuid);
          if (ci >= 0)
            chars[ci] = CharacteristicInfo(uuid: uuid, name: name, value: val, flags: chars[ci].flags);
          else
            chars.add(CharacteristicInfo(uuid: uuid, name: name, value: val, flags: []));
          connectedDevices[idx] = ConnectedDevice(mac: mac, name: connectedDevices[idx].name, characteristics: chars);
        }
        addLog('[$name]: $val');
        break;
      case 'url_update':
        currentUrl = p['url'];
        addLog('[URL] Playing: ${p['url']}');
        break;
      case 'url_history':
        if (p['history'] != null)
          urlHistory = (p['history'] as List).map((d) => HistoryItem.fromJson(d)).toList();
        break;
      case 'url_rejected':
        addLog('[REJECTED] ${p['reason']}: ${p['url']}');
        break;
      case 'player_state':
        addLog('[PLAYER] ${p['cmd']}');
        break;
    }
    notifyListeners();
  }
}
