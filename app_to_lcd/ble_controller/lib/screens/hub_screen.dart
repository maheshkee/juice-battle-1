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
import '../screens/schedule_screen.dart';
import '../screens/watch_later_screen.dart';
import '../services/watch_later_service.dart';
import '../services/bt_audio_service.dart';
import '../screens/bt_devices_screen.dart';
import '../screens/history_screen.dart';
import '../screens/playlists_screen.dart';
import '../screens/whistle_screen.dart';
import '../services/playlist_service.dart';
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
            if (board.scheduleDirty) {
              ble.sendSchedule(board.scheduleEntries);
              board.markScheduleClean();
            }
            final pl = context.read<PlaylistService>();
            if (pl.dirty) {
              ble.sendPlaylists(pl.toJsonList());
              pl.markClean();
            }
          });
          final wl       = context.read<WatchLaterService>();
          final removals = wl.flushPendingRemovals();
          for (final url in removals) ble.watchLaterRemove(url);
          final pending = wl.flushPending();
          for (final item in pending) ble.watchLaterAdd(item.url, item.title, item.videoId);
          if (removals.isEmpty) ble.watchLaterGet();
        }
        if (s == ConnState.disconnected) {
          board.addLog('[APP] Disconnected');
          stopKeepAlive();
        }
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
          context.read<WatchLaterService>().syncFromBoard(board.watchLaterItems);
        }
        if (evt.event == 'playlist_update') {
          final pl             = context.read<PlaylistService>();
          final boardPlaylists = evt.data['playlists'] as List? ?? [];
          if (pl.playlists.isEmpty && boardPlaylists.isNotEmpty) {
            pl.syncFromBoard(boardPlaylists);
          }
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
          final b = context.read<BoardState>();
          b.scheduleEntries = List.from(entries);
          b.saveSchedule();
          if (ble.state == ConnState.connected) {
            ble.sendSchedule(entries);
            b.markScheduleClean();
          }
          b.notifyListeners();
        },
      ),
    ));
  }

  void _openWhistle() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WhistleScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final ble       = context.watch<BleService>();
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
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(children: [

                Selector<BoardState, (String, bool)>(
                  selector: (_, b) => (b.mode, b.ledOn),
                  builder: (ctx, _, __) {
                    final b = ctx.read<BoardState>();
                    return LedModeBar(
                      ledOn:       b.ledOn,
                      mode:        b.mode,
                      enabled:     connected,
                      onLedToggle: () {
                        final board = ctx.read<BoardState>();
                        ble.sendLedToggle();
                        board.ledOn = !board.ledOn;
                        board.notifyListeners();
                      },
                      onModeIdle: () {
                        final board = ctx.read<BoardState>();
                        if (board.mode == 'idle') {
                          ble.setModeYouTube(); board.mode = 'youtube';
                        } else {
                          ble.setModeIdle(); board.mode = 'idle';
                        }
                        board.notifyListeners();
                      },
                      onModeClock: () {
                        final board = ctx.read<BoardState>();
                        if (board.mode == 'clock') {
                          ble.setModeYouTube(); board.mode = 'youtube';
                        } else {
                          ble.setModeClock(); board.mode = 'clock';
                        }
                        board.notifyListeners();
                      },
                      onSchedule: _openSchedule,
                      onWhistle:  _openWhistle,
                    );
                  },
                ),

                const SizedBox(height: 12),

                Selector<BoardState, List<ScheduleEntry>>(
                  selector: (_, b) => b.scheduleEntries,
                  shouldRebuild: (a, b) => a.length != b.length || a != b,
                  builder: (ctx, entries, __) => _TodayCard(
                    entries:   entries,
                    connected: connected,
                    ble:       ble,
                    onManage:  _openSchedule,
                  ),
                ),

                const SizedBox(height: 12),

                Selector<BoardState, (String?, List<HistoryItem>)>(
                  selector: (_, b) => (b.currentUrl, b.urlHistory),
                  shouldRebuild: (a, b) =>
                    a.$1 != b.$1 || a.$2.length != b.$2.length,
                  builder: (ctx, data, __) => YouTubeSection(
                    currentUrl: data.$1,
                    history:    data.$2,
                    enabled:    connected,
                    onSend: (url, title) {
                      ble.sendUrlWithTitle(url, title);
                      final board = ctx.read<BoardState>();
                      if (title.isNotEmpty) board.nowPlaying = title;
                      board.urlHistory.insert(0, HistoryItem(
                        url:   url,
                        time:  DateTime.now().toString().substring(11, 16),
                        title: title));
                      board.notifyListeners();
                    },
                  ),
                ),

                const SizedBox(height: 12),

                Selector<BoardState, String?>(
                  selector: (_, b) => b.nowPlaying,
                  builder: (ctx, nowPlaying, __) => PlayerControls(
                    enabled:       connected,
                    nowPlaying:    nowPlaying,
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
                  ),
                ),

                const SizedBox(height: 12),
                const _PlaylistsSection(),
                const SizedBox(height: 12),

                Selector<BoardState, int>(
                  selector: (_, b) => b.logs.length,
                  builder: (ctx, _, __) {
                    final board = ctx.read<BoardState>();
                    return LogConsole(
                      logs:    board.logs,
                      onClear: () {
                        board.logs.clear();
                        board.notifyListeners();
                      },
                    );
                  },
                ),

              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(BleService ble) {
    final live = ble.state == ConnState.connected;
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
            boxShadow: live ? [BoxShadow(
              color: const Color(0xFF00D4FF).withOpacity(0.3),
              blurRadius: 12, offset: const Offset(0, 4))] : []),
          child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20)),
        const SizedBox(width: 12),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('BLE HUB', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white,
            letterSpacing: 1.5)),
          Text('Arduino UNO Q', style: TextStyle(
            fontSize: 10, color: Color(0xFF3D5068), letterSpacing: 0.5)),
        ]),
        const Spacer(),
        const SizedBox(width: 8),
        Selector<BoardState, int>(
          selector: (_, b) => b.urlHistory.length,
          builder: (ctx, count, __) => GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen())),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFFF3D71).withOpacity(0.07),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFFFF3D71).withOpacity(0.15))),
              child: Stack(alignment: Alignment.center, children: [
                const Icon(Icons.history, color: Color(0xFFFF3D71), size: 18),
                if (count > 0) Positioned(top: 6, right: 6,
                  child: Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Color(0xFFFF3D71)))),
              ])))),
        const SizedBox(width: 8),
        Selector<WatchLaterService, (int, int)>(
          selector: (_, wl) => (wl.pendingCount, wl.items.length),
          builder: (ctx, data, __) => GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WatchLaterScreen())),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF0A84FF).withOpacity(0.07),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFF0A84FF).withOpacity(0.15))),
              child: Stack(alignment: Alignment.center, children: [
                const Icon(Icons.bookmark_outline_rounded,
                  color: Color(0xFF0A84FF), size: 18),
                if (data.$1 > 0) Positioned(top: 5, right: 5,
                  child: Container(width: 7, height: 7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Color(0xFFFF9F0A))))
                else if (data.$2 > 0) Positioned(top: 6, right: 6,
                  child: Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Color(0xFF0A84FF)))),
              ])))),
        const SizedBox(width: 8),
        Selector<BoardState, String>(
          selector: (_, b) => b.btAudioStatus,
          builder: (ctx, status, __) => GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BtDevicesScreen())),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF00D4FF).withOpacity(0.07),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.15))),
              child: Stack(alignment: Alignment.center, children: [
                const Icon(Icons.bluetooth_rounded,
                  color: Color(0xFF00D4FF), size: 18),
                if (status == 'connected') Positioned(top: 7, right: 7,
                  child: Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Color(0xFF34C759)))),
              ])))),
      ]),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final List<ScheduleEntry> entries;
  final bool connected;
  final BleService ble;
  final VoidCallback onManage;
  const _TodayCard({required this.entries, required this.connected,
    required this.ble, required this.onManage});

  @override
  Widget build(BuildContext context) {
    final now      = DateTime.now();
    final today    = entries.where((e) =>
        e.date.year == now.year && e.date.month == now.month &&
        e.date.day  == now.day).firstOrNull;
    final upcoming = entries
        .where((e) => e.date.isAfter(DateTime(now.year, now.month, now.day)))
        .toList()..sort((a, b) => a.date.compareTo(b.date));
    if (today == null && upcoming.isEmpty) return const SizedBox.shrink();

    final mnShort = ['Jan','Feb','Mar','Apr','May','Jun',
                     'Jul','Aug','Sep','Oct','Nov','Dec'];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: today != null
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
              child: Text(today != null ? 'TODAY' : 'UPCOMING',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: today != null
                    ? const Color(0xFFFFB347) : const Color(0xFF3D5068)))),
            const Spacer(),
            GestureDetector(onTap: onManage,
              child: const Text('Manage \u2192',
                style: TextStyle(fontSize: 10, color: Color(0xFF3D5068)))),
          ]),
        ),
        if (today != null)
          ...today.playlist.asMap().entries.map((e) =>
            _todayTile(context, e.value, e.key))
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

  Widget _todayTile(BuildContext context, QueueItem item, int idx) =>
    GestureDetector(
      onTap: connected ? () => ble.sendUrlWithTitle(item.url, item.title) : null,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: connected
            ? const Color(0xFFFFB347).withOpacity(0.05)
            : const Color(0xFF131E2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: connected
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
          if (connected) const Icon(Icons.play_circle_outline,
            color: Color(0xFFFFB347), size: 18),
        ]),
      ),
    );
}

class _PlaylistsSection extends StatelessWidget {
  const _PlaylistsSection();

  @override
  Widget build(BuildContext context) {
    final ble       = context.read<BleService>();
    final connected = ble.state == ConnState.connected;
    final ps        = context.watch<PlaylistService>();
    final preview   = ps.playlists.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2A3A))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.queue_music, color: Color(0xFF30D158), size: 16),
          const SizedBox(width: 8),
          const Text('PLAYLISTS', style: TextStyle(fontSize: 10,
            fontWeight: FontWeight.w700, color: Color(0xFF30D158),
            letterSpacing: 1.5)),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PlaylistsScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2A3A),
                borderRadius: BorderRadius.circular(8)),
              child: const Text('See All', style: TextStyle(
                fontSize: 10, color: Color(0xFF30D158))))),
        ]),
        if (ps.playlists.isEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PlaylistsScreen())),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF30D158).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF30D158).withOpacity(0.2))),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
                Icon(Icons.add, color: Color(0xFF30D158), size: 16),
                SizedBox(width: 6),
                Text('Create Playlist', style: TextStyle(
                  fontSize: 13, color: Color(0xFF30D158))),
              ]))),
        ] else ...[
          const SizedBox(height: 10),
          ...preview.map((p) => GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlaylistDetailScreen(playlistId: p.id))),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2236),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E2A3A))),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF30D158).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.queue_music,
                    color: Color(0xFF30D158), size: 16)),
                const SizedBox(width: 10),
                Expanded(child: Text(p.name, style: const TextStyle(
                  fontSize: 13, color: Colors.white,
                  fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis)),
                Text('${p.videos.length}', style: const TextStyle(
                  fontSize: 11, color: Color(0xFF4A5568))),
              ]),
            ),
          )),
        ],
      ]),
    );
  }
}
