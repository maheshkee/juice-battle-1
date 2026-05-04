import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/board_event.dart';

class BoardState extends ChangeNotifier {
  bool   ledOn      = false;
  String mode       = 'idle';
  String? currentUrl;
  String? nowPlaying;
  List<HistoryItem> urlHistory         = [];
  List<Map<String, dynamic>> scanResults      = [];
  List<Map<String, dynamic>> connectedDevices = [];
  List<Map<String, dynamic>> trustedDevices   = [];
  bool   scanning      = false;
  List<String> logs    = [];
  QueueStatus  queueStatus    = QueueStatus.empty();
  List<ScheduleEntry> scheduleEntries = [];
  List<WatchLaterItem> watchLaterItems  = [];
  String btAudioStatus  = 'disconnected';
  String btAudioDevice  = '';
  String btAudioName    = '';
  List<Map<String, dynamic>> btPairedDevices = [];

  BoardState() {
    _loadBtConnected();
  }

  Future<void> _loadBtConnected() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mac  = prefs.getString('bt_connected_mac')  ?? '';
      final name = prefs.getString('bt_connected_name') ?? '';
      if (mac.isNotEmpty) {
        btAudioStatus = 'connected';
        btAudioDevice = mac;
        btAudioName   = name;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveBtConnected(String mac, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bt_connected_mac',  mac);
      await prefs.setString('bt_connected_name', name);
    } catch (_) {}
  }

  Future<void> _clearBtConnected() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('bt_connected_mac');
      await prefs.remove('bt_connected_name');
    } catch (_) {}
  }

  void addLog(String msg) {
    logs.insert(0, msg);
    if (logs.length > 200) logs.removeLast();
    notifyListeners();
  }

  void applyEvent(BoardEvent evt) {
    final d = evt.data;
    switch (evt.event) {
      case 'full_status':
        ledOn      = d['led']      ?? ledOn;
        mode       = d['mode']     ?? mode;
        currentUrl = d['current_url'];
        urlHistory = (d['history'] as List? ?? [])
            .map((e) => HistoryItem.fromJson(e)).toList();
        scanning   = d['scanning'] ?? scanning;
        scanResults      = List<Map<String, dynamic>>.from(d['scan_results'] ?? []);
        connectedDevices = List<Map<String, dynamic>>.from(d['connected_devices'] ?? []);
        trustedDevices   = List<Map<String, dynamic>>.from(
            (d['trusted'] as List? ?? []).map((e) =>
              {'mac': e['mac'], 'name': e['name']}));
        if (d['queue_status'] != null)
          queueStatus = QueueStatus.fromJson(d['queue_status']);
        if (d['schedule'] != null)
          scheduleEntries = (d['schedule'] as List? ?? [])
              .map((e) => ScheduleEntry.fromJson(e)).toList();
        final np = (d['now_playing'] ?? '') as String;
        nowPlaying = np.isNotEmpty ? np : nowPlaying;
        break;
      case 'led_status':
        ledOn = d['state'] ?? ledOn;
        break;
      case 'mode_update':
        mode = d['mode'] ?? mode;
        break;
      case 'url_update':
        currentUrl = d['url'];
        break;
      case 'url_history':
        urlHistory = (d['history'] as List? ?? [])
            .map((e) => HistoryItem.fromJson(e)).toList();
        if (nowPlaying != null) {
          for (final item in urlHistory) {
            if (item.title.isNotEmpty &&
                (nowPlaying == item.url || nowPlaying!.length == 11)) {
              nowPlaying = item.title;
              break;
            }
          }
        }
        break;
      case 'scan_status':
        scanning = d['scanning'] ?? scanning;
        break;
      case 'scan_results':
        scanResults = List<Map<String, dynamic>>.from(d['devices'] ?? []);
        break;
      case 'connected_devices':
        connectedDevices = List<Map<String, dynamic>>.from(d['devices'] ?? []);
        break;
      case 'trusted_devices':
        trustedDevices = List<Map<String, dynamic>>.from(
            (d['devices'] as List? ?? []).map((e) =>
              {'mac': e['mac'], 'name': e['name']}));
        break;
      case 'device_connected':
        addLog('[BLE] Connected: ${d['name'] ?? d['mac']}');
        break;
      case 'device_disconnected':
        addLog('[BLE] Disconnected: ${d['mac']}');
        break;
      case 'queue_status':
        queueStatus = QueueStatus.fromJson(d);
        break;
      case 'schedule_update':
        scheduleEntries = (d['entries'] as List? ?? [])
            .map((e) => ScheduleEntry.fromJson(e)).toList();
        break;
      case 'watchlater_update':
        watchLaterItems = (d['items'] as List? ?? [])
            .map((e) => WatchLaterItem.fromJson(e)).toList();
        break;
      case 'now_playing':
        final t = (d['title'] ?? '') as String;
        final v = (d['video_id'] ?? '') as String;
        nowPlaying = t.isNotEmpty ? t : (v.isNotEmpty ? v : null);
        break;
      case 'player_state':
        if (d['cmd'] == 'stop') { mode = 'idle'; nowPlaying = null; }
        break;
      case 'bt_audio_connected':
        btAudioStatus = 'connected';
        btAudioDevice = d['mac']  ?? '';
        btAudioName   = d['name'] ?? d['mac'] ?? '';
        _saveBtConnected(btAudioDevice, btAudioName);
        break;
      case 'bt_audio_disconnected':
        btAudioStatus = 'disconnected';
        btAudioDevice = '';
        btAudioName   = '';
        _clearBtConnected();
        break;
      case 'bt_paired_devices':
        btPairedDevices = List<Map<String, dynamic>>.from(
            (d['devices'] as List? ?? []).map((e) =>
              {'mac': e['mac'], 'name': e['name']}));
        break;
    }
    notifyListeners();
  }
}
