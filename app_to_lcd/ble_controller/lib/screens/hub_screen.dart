import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/board_state.dart';
import '../models/board_event.dart';
import '../widgets/connection_bar.dart';
import '../widgets/youtube_section.dart';
import '../widgets/player_controls.dart';
import '../widgets/log_console.dart';
import '../widgets/led_mode_bar.dart';
import '../widgets/queue_section.dart';
import '../screens/schedule_screen.dart';
import '../screens/watch_later_screen.dart';
import '../services/watch_later_service.dart';
import '../services/bt_audio_service.dart';
import '../screens/bt_devices_screen.dart';
import '../main.dart' show startKeepAlive, stopKeepAlive;

class HubScreen extends StatefulWidget {
  const HubScreen({super.key});
  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  final List<StreamSubscription> _subs        = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _requestPermissions();
      if (!mounted) return;
      final ble   = context.read<BleService>();
      final board = context.read<BoardState>();
      _subs.add(ble.connState.listen((s) {
        setState(() {});
        if (s == ConnState.connected) {
          board.addLog('[APP] Connected to board');
          startKeepAlive();
          Future.delayed(const Duration(milliseconds: 500), () {
            ble.getStatus();
          });
          final wl      = context.read<WatchLaterService>();
          final pending = wl.flushPending();
          for (final item in pending) {
            ble.watchLaterAdd(item.url, item.title, item.videoId);
          }
          ble.watchLaterGet();
        }
        if (s == ConnState.disconnected)
          { board.addLog('[APP] Disconnected'); stopKeepAlive(); }
      }));
      _subs.add(ble.devName.listen((_) => setState(() {})));
      _subs.add(ble.logs.listen((msg) => board.addLog(msg)));
      _subs.add(ble.events.listen((evt) {
        board.applyEvent(evt);
        final btAudio = context.read<BtAudioService>();
        if (evt.event == 'bt_audio_connected') {
          final mac  = evt.data['mac'] as String? ?? '';
          final name = evt.data['name'] as String? ?? mac;
          btAudio.setConnected(mac, name);
        } else if (evt.event == 'bt_audio_disconnected') {
          btAudio.setDisconnected();
        } else if (evt.event == 'bt_audio_error') {
          final mac = evt.data['mac'] as String? ?? '';
          btAudio.setError(mac);
        } else if (evt.event == 'bt_paired_devices') {
          final devices = List<Map<String, dynamic>>.from(
            (evt.data['devices'] as List? ?? []).map((e) =>
              {'mac': e['mac'] as String, 'name': e['name'] as String}));
          btAudio.setPairedDevices(devices);
        } else if (evt.event == 'bt_forgotten') {
          final mac = evt.data['mac'] as String? ?? '';
          if (mac.isNotEmpty) btAudio.setForgotten(mac);
        }
        if (evt.event == 'watchlater_update') {
          final wl = context.read<WatchLaterService>();
          wl.syncFromBoard(board.watchLaterItems);
        }
      }));
      ble.startScan();
    });
  }

  Future<void> _requestPermissions() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect,
           Permission.location].request();
  }

  @override
  void dispose() {
    for (var s in _subs) s.cancel();
    super.dispose();
  }

  void _openSchedule() {
    final ble   = context.read<BleService>();
    final board = context.read<BoardState>();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScheduleScreen(
        initialEntries: board.scheduleEntries,
        enabled:        ble.state == ConnState.connected,
        onSave: (entries) {
          ble.sendSchedule(entries);
          context.read<BoardState>().scheduleEntries = List.from(entries);
          context.read<BoardState>().notifyListeners();
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ble       = context.watch<BleService>();
    final board     = context.watch<BoardState>();
    final connected = ble.state == ConnState.connected;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(ble),
          ConnectionBar(
            state:        ble.state,
            onScan:       () => ble.startScan(),
            onDisconnect: () => ble.disconnect()),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(children: [
                LedModeBar(
                  ledOn:       board.ledOn,
                  mode:        board.mode,
                  enabled:     connected,
                  onLedToggle: () {
                    ble.sendLedToggle();
                    context.read<BoardState>().ledOn = !context.read<BoardState>().ledOn;
                    context.read<BoardState>().notifyListeners();
                  },
                  onModeIdle: () {
                    ble.setModeIdle();
                    context.read<BoardState>().mode = 'idle';
                    context.read<BoardState>().notifyListeners();
                  },
                  onModeClock: () {
                    ble.setModeClock();
                    context.read<BoardState>().mode = 'clock';
                    context.read<BoardState>().notifyListeners();
                  },
                  onSchedule: _openSchedule,
                ),
                const SizedBox(height: 12),
                _buildTodayCard(board, ble),
                const SizedBox(height: 12),
                YouTubeSection(
                  currentUrl: board.currentUrl,
                  history:    board.urlHistory,
                  enabled:    connected,
                  onSend: (url, title) {
                    ble.sendUrlWithTitle(url, title);
                    context.read<BoardState>().nowPlaying = title.isNotEmpty ? title : url;
                    context.read<BoardState>().notifyListeners();
                    context.read<BoardState>().urlHistory.insert(0,
                      HistoryItem(url: url, time: DateTime.now().toString().substring(11, 16), title: title));
                    context.read<BoardState>().notifyListeners();
                  },
                ),
                const SizedBox(height: 12),
                PlayerControls(
                  enabled:       connected,
                  onPause:       () => ble.playerPause(),
                  onResume:      () => ble.playerResume(),
                  onStop:        () => ble.playerStop(),
                  onMute:        () => ble.playerMute(),
                  onUnmute:      () => ble.playerUnmute(),
                  onVolUp:       () => ble.playerVolUp(),
                  onVolDown:     () => ble.playerVolDown(),
                  onSeekForward: () => ble.playerSeekForward(),
                  onSeekBack:    () => ble.playerSeekBack(),
                  onReplay:      () => ble.playerReplay(),
                  onQuality:     (q) => ble.playerQuality(q),
                  nowPlaying:    board.nowPlaying,
                ),
                const SizedBox(height: 12),
                QueueSection(
                  status:      board.queueStatus,
                  enabled:     connected,
                  onSendQueue: (items) => ble.sendQueue(items),
                  onPlay:      () => ble.queuePlay(),
                  onPause:     () => ble.queuePause(),
                  onResume:    () => ble.queueResume(),
                  onSkip:      () => ble.queueSkip(),
                  onReplay:    () => ble.queueReplay(),
                  onStop:      () => ble.queueStop(),
                  onGoto:      (i) => ble.queueGoto(i),
                ),
                const SizedBox(height: 12),
                LogConsole(
                  logs:    board.logs,
                  onClear: () { board.logs.clear(); board.notifyListeners(); }),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildTodayCard(BoardState board, BleService ble) {
    final now   = DateTime.now();
    final today = board.scheduleEntries.where((e) =>
        e.date.year == now.year &&
        e.date.month == now.month &&
        e.date.day   == now.day).firstOrNull;
    final upcoming = board.scheduleEntries
        .where((e) => e.date.isAfter(DateTime(now.year, now.month, now.day)))
        .toList()..sort((a, b) => a.date.compareTo(b.date));
    if (today == null && upcoming.isEmpty) return const SizedBox.shrink();
    final connected = ble.state == ConnState.connected;
    final mnShort   = ['Jan','Feb','Mar','Apr','May','Jun',
                       'Jul','Aug','Sep','Oct','Nov','Dec'];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: today != null
            ? const Color(0xFFFFB347).withOpacity(0.25)
            : const Color(0xFF1A2840))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: today != null
                  ? const Color(0xFFFFB347).withOpacity(0.12)
                  : const Color(0xFF1A2840),
                borderRadius: BorderRadius.circular(6)),
              child: Text(
                today != null ? 'TODAY' : 'UPCOMING',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: today != null
                    ? const Color(0xFFFFB347)
                    : const Color(0xFF3D5068)))),
            const Spacer(),
            GestureDetector(
              onTap: _openSchedule,
              child: const Text('Manage →',
                style: TextStyle(fontSize: 10, color: Color(0xFF3D5068)))),
          ]),
        ),
        if (today != null)
          ...today.playlist.asMap().entries.map((e) =>
            _todayTile(e.value, e.key, connected, ble))
        else
          ...upcoming.take(2).map((entry) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF131E2E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1A2840))),
                child: Column(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  Text(mnShort[entry.date.month-1], style: const TextStyle(
                    fontSize: 7, color: Color(0xFF3D5068),
                    fontWeight: FontWeight.w700)),
                  Text('${entry.date.day}', style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w900,
                    color: Colors.white, height: 1)),
                ])),
              const SizedBox(width: 10),
              Text('${entry.playlist.length} video${entry.playlist.length == 1 ? '' : 's'} scheduled',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5A7A9A))),
            ]),
          )),
        const SizedBox(height: 4),
      ]),
    );
  }

  Widget _todayTile(QueueItem item, int idx, bool connected, BleService ble) =>
    GestureDetector(
      onTap: connected ? () => ble.sendUrl(item.url) : null,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: connected
            ? const Color(0xFFFFB347).withOpacity(0.05)
            : const Color(0xFF131E2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: connected
              ? const Color(0xFFFFB347).withOpacity(0.15)
              : const Color(0xFF1A2840))),
        child: Row(children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFFFFB347).withOpacity(0.10),
              borderRadius: BorderRadius.circular(6)),
            child: Center(child: Text('${idx+1}', style: const TextStyle(
              fontSize: 10, color: Color(0xFFFFB347),
              fontWeight: FontWeight.w800)))),
          const SizedBox(width: 10),
          Expanded(child: Text(item.title, style: const TextStyle(
            fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis)),
          if (connected)
            const Icon(Icons.play_circle_outline,
              color: Color(0xFFFFB347), size: 18),
        ]),
      ),
    );

  void _showHistory(BoardState board, BleService ble) {
    if (board.urlHistory.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E3048),
            borderRadius: BorderRadius.circular(2))),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Recent Videos', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white))),
        Flexible(child: ListView(shrinkWrap: true, children: [
          ...board.urlHistory.take(15).map((item) {
            final display = item.title.isNotEmpty ? item.title : item.url;
            return ListTile(
              leading: const Icon(Icons.play_circle_outline,
                color: Color(0xFFFF3D71), size: 20),
              title: Text(display, style: const TextStyle(
                fontSize: 13, color: Colors.white),
                overflow: TextOverflow.ellipsis),
              subtitle: Text(item.time, style: const TextStyle(
                fontSize: 10, color: Color(0xFF4B6070))),
              onTap: ble.state == ConnState.connected ? () {
                ble.sendUrl(item.url);
                Navigator.pop(context);
              } : null,
            );
          }),
        ])),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _buildHeader(BleService ble) {
    final live  = ble.state == ConnState.connected;
    final c     = live ? const Color(0xFF00D4FF) : const Color(0xFF3D5068);
    final cGlow = live ? const Color(0xFF00D4FF) : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF00D4FF), Color(0xFF0052D4)]),
            borderRadius: BorderRadius.circular(11),
            boxShadow: live ? [
              BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.3),
                blurRadius: 12, offset: const Offset(0, 4))] : [],
          ),
          child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20)),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('BLE HUB', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white,
            letterSpacing: 1.5)),
          const Text('Arduino UNO Q', style: TextStyle(
            fontSize: 10, color: Color(0xFF3D5068), letterSpacing: 0.5)),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: c.withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withOpacity(0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c,
                boxShadow: [BoxShadow(color: cGlow.withOpacity(0.8),
                  blurRadius: 6)])),
            const SizedBox(width: 6),
            Text(live ? 'LIVE' : 'OFFLINE', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: c, letterSpacing: 1)),
          ])),
        const SizedBox(width: 8),
        Builder(builder: (ctx) {
          final board = ctx.watch<BoardState>();
          final ble   = ctx.watch<BleService>();
          return GestureDetector(
            onTap: () => _showHistory(board, ble),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFFF3D71).withOpacity(0.07),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: const Color(0xFFFF3D71).withOpacity(0.15))),
              child: Stack(alignment: Alignment.center, children: [
                const Icon(Icons.history, color: Color(0xFFFF3D71), size: 18),
                if (board.urlHistory.isNotEmpty)
                  Positioned(top: 6, right: 6,
                    child: Container(width: 6, height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFF3D71)))),
              ])));
        }),
        const SizedBox(width: 8),
        Builder(builder: (ctx) {
          final wl = ctx.watch<WatchLaterService>();
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WatchLaterScreen())),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF0A84FF).withOpacity(0.07),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: const Color(0xFF0A84FF).withOpacity(0.15))),
              child: Stack(alignment: Alignment.center, children: [
                const Icon(Icons.bookmark_outline_rounded,
                  color: Color(0xFF0A84FF), size: 18),
                if (wl.items.isNotEmpty)
                  Positioned(top: 6, right: 6,
                    child: Container(width: 6, height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF0A84FF)))),
                if (wl.pendingCount > 0)
                  Positioned(top: 5, right: 5,
                    child: Container(width: 8, height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFF9F0A)))),
              ])));
        }),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BtDevicesScreen())),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withOpacity(0.07),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: const Color(0xFF00D4FF).withOpacity(0.15))),
            child: Stack(alignment: Alignment.center, children: [
              const Icon(Icons.bluetooth_rounded,
                color: Color(0xFF00D4FF), size: 18),
              if (context.watch<BoardState>().btAudioStatus == 'connected')
                Positioned(top: 7, right: 7,
                  child: Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF34C759)))),
            ]))),
      ]),
    );
  }
}
