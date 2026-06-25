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
import 'package:wifi_iot/wifi_iot.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
          board.resetHistoryFlag();
          startKeepAlive();
          Future.delayed(const Duration(milliseconds: 500), () {

            if (board.scheduleEntries.isNotEmpty) {
              ble.sendSchedule(board.scheduleEntries);
              board.markScheduleClean();
            }
            final pl = context.read<PlaylistService>();
            if (pl.playlists.isNotEmpty) {
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

    // turn on bluetooth if off
    final btState = await FlutterBluePlus.adapterState.first;
    if (btState == BluetoothAdapterState.off) {
      await FlutterBluePlus.turnOn();
      // wait up to 10s for BT to turn on
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () => BluetoothAdapterState.off);
    }

    // turn on location if off
    final locationOn = await Geolocator.isLocationServiceEnabled();
    if (!locationOn) {
      await Geolocator.openLocationSettings();
      // wait a moment for user to enable
      await Future.delayed(const Duration(seconds: 1));
    }
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
      drawer: _buildDrawer(context, ble, connected),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(ble),
          Selector<BoardState, String>(
            selector: (_, b) => b.boardName,
            builder: (_, name, __) => ConnectionBar(
              state:        ble.state,
              onScan:       () => ble.startScan(),
              onDisconnect: () => ble.disconnect(),
              boardName:    name.isNotEmpty ? name : 'BLE-Hub')),
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
                          if (board.nowPlaying != null && board.nowPlaying!.isNotEmpty) {
                            ble.setModeYouTube(); board.mode = 'youtube';
                            board.notifyListeners();
                          }
                          return;
                        }
                        ble.setModeIdle(); board.mode = 'idle';
                        board.notifyListeners();
                      },
                      onModeClock: () {
                        final board = ctx.read<BoardState>();
                        if (board.mode == 'clock') {
                          if (board.nowPlaying != null && board.nowPlaying!.isNotEmpty) {
                            ble.setModeYouTube(); board.mode = 'youtube';
                            board.notifyListeners();
                          }
                          return;
                        }
                        ble.setModeClock(); board.mode = 'clock';
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

                Selector<BoardState, (String?, String)>(
                  selector: (_, b) => (b.nowPlaying, b.mode),
                  builder: (ctx, data, __) => PlayerControls(
                    enabled:       connected && data.$2 == 'youtube',
                    nowPlaying:    data.$1,

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

  Widget _buildDrawer(BuildContext context, BleService ble, bool connected) {
    return Drawer(
      backgroundColor: const Color(0xFF0D1520),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF00D4FF), Color(0xFF0052D4)]),
                    borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.hub_rounded, color: Colors.white, size: 16)),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Display', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
                  Text('Choose how the board screen looks', style: TextStyle(
                    fontSize: 11, color: Color(0xFF3D5068))),
                ]),
              ]),
            ),
            const Divider(color: Color(0xFF1A2840), height: 1),
            Selector<BoardState, String>(
              selector: (_, b) => b.displayMode,
              builder: (ctx, mode, __) {
                final connected = context.read<BleService>().state == ConnState.connected;
                final isSplit = mode == 'split';
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(children: [
                    Icon(
                      isSplit
                        ? Icons.view_sidebar_rounded
                        : Icons.picture_in_picture_alt_rounded,
                      color: isSplit
                        ? const Color(0xFF30D158)
                        : const Color(0xFF0052D4),
                      size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isSplit ? 'Split screen' : 'Overlay',
                          style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500,
                            color: Colors.white)),
                        Text(
                          isSplit
                            ? 'YouTube left, whistle panel right'
                            : 'YouTube fullscreen + whistle corner',
                          style: const TextStyle(
                            fontSize: 11, color: Color(0xFF3D5068))),
                      ],
                    )),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        final board = ctx.read<BoardState>();
                        final newMode = isSplit ? 'overlay' : 'split';
                        board.displayMode = newMode;
                        board.saveDisplayMode();
                        board.notifyListeners();
                        if (connected) ble.setDisplayMode(newMode);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44, height: 26,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          color: isSplit
                            ? const Color(0xFF30D158)
                            : const Color(0xFF2A3A4A)),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 200),
                          alignment: isSplit
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.all(3),
                            width: 20, height: 20,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ]),
                );
              },
            ),
            const SizedBox(height: 8),
            const Divider(color: Color(0xFF1A2840), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => WifiProvisionDialog(
                      ble:       ble,
                      connected: connected,
                    ),
                  );
                },
                child: Row(children: [
                  const Icon(Icons.wifi_rounded,
                    color: Color(0xFF00D4FF), size: 20),
                  const SizedBox(width: 10),
                  const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WiFi', style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500,
                        color: Colors.white)),
                      Text('Connect board to a network', style: TextStyle(
                        fontSize: 11, color: Color(0xFF3D5068))),
                    ],
                  )),
                  const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFF3D5068), size: 18),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BleService ble) {
    final live = ble.state == ConnState.connected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
      child: Row(children: [
        GestureDetector(
          onTap: () => _scaffoldKey.currentState?.openDrawer(),
          child: Container(
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
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Selector<BoardState, String>(
            selector: (_, b) => b.boardName,
            builder: (_, name, __) => Text(
              name.isNotEmpty ? name : 'BLE HUB',
              style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white,
                letterSpacing: 1.5))),
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

class _DrawerModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _DrawerModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
            ? accentColor.withOpacity(0.08)
            : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
              ? accentColor.withOpacity(0.4)
              : const Color(0xFF1A2840),
            width: selected ? 1.5 : 1.0)),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: selected
                ? accentColor.withOpacity(0.15)
                : const Color(0xFF1A2840),
              borderRadius: BorderRadius.circular(10)),
            child: Icon(icon,
              color: selected ? accentColor : const Color(0xFF3D5068),
              size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF5A7A9A))),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(
                fontSize: 10,
                color: selected
                  ? accentColor.withOpacity(0.6)
                  : const Color(0xFF3D5068))),
            ],
          )),
          if (selected)
            Icon(Icons.check_circle_rounded, color: accentColor, size: 18),
        ]),
      ),
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

class WifiProvisionDialog extends StatefulWidget {
  final BleService ble;
  final bool connected;
  const WifiProvisionDialog({super.key, required this.ble, required this.connected});
  @override
  State<WifiProvisionDialog> createState() => _WifiProvisionDialogState();
}

class _WifiProvisionDialogState extends State<WifiProvisionDialog> {
  List<WifiNetwork> _networks = [];
  bool   _scanning    = false;
  bool   _sending     = false;
  bool?  _result      = null;
  String _resultMsg   = '';
  String _selectedSsid = '';
  final  _pwdController = TextEditingController();
  bool   _pwdVisible  = false;

  @override
  void initState() {
    super.initState();
    _scan();
    final board = context.read<BoardState>();
    board.onWifiResult = (success, ssid, error) {
      if (!mounted) return;
      setState(() {
        _sending   = false;
        _result    = success;
        _resultMsg = success ? 'Connected to $ssid' : 'Failed: $error';
      });
    };
  }

  @override
  void dispose() {
    final board = context.read<BoardState>();
    board.onWifiResult = null;
    _pwdController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() { _scanning = true; _networks = []; });
    try {
      final results = await WiFiForIoTPlugin.loadWifiList() ?? [];
      final seen = <String>{};
      final unique = <WifiNetwork>[];
      for (final r in results) {
        final ssid = r.ssid ?? '';
        if (ssid.isNotEmpty && seen.add(ssid)) unique.add(r);
      }
      unique.sort((a, b) => (b.level ?? -100).compareTo(a.level ?? -100));
      setState(() { _networks = unique; });
    } catch (_) {}
    setState(() { _scanning = false; });
  }

  IconData _signalIcon(int level) {
    if (level >= -50) return Icons.signal_wifi_4_bar_rounded;
    if (level >= -60) return Icons.network_wifi_3_bar_rounded;
    if (level >= -70) return Icons.network_wifi_2_bar_rounded;
    return Icons.network_wifi_1_bar_rounded;
  }

  void _selectNetwork(String ssid) {
    setState(() { _selectedSsid = ssid; _result = null; _resultMsg = ''; });
  }

  Future<void> _connect() async {
    if (_selectedSsid.isEmpty) return;
    setState(() { _sending = true; _result = null; _resultMsg = ''; });
    await widget.ble.wifiProvision(_selectedSsid, _pwdController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0D1520),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF00D4FF).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.wifi_rounded,
                color: Color(0xFF00D4FF), size: 18)),
            const SizedBox(width: 10),
            const Expanded(child: Text('Connect Board to WiFi',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                color: Colors.white))),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(Icons.close_rounded,
                color: Color(0xFF3D5068), size: 20)),
          ]),

          const SizedBox(height: 16),

          if (!widget.connected) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3D71).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFF3D71).withOpacity(0.2))),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFF3D71), size: 16),
                SizedBox(width: 8),
                Expanded(child: Text('Connect to board via BLE first',
                  style: TextStyle(fontSize: 12, color: Color(0xFFFF3D71)))),
              ])),
          ] else if (_result != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _result!
                  ? const Color(0xFF30D158).withOpacity(0.08)
                  : const Color(0xFFFF3D71).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _result!
                    ? const Color(0xFF30D158).withOpacity(0.2)
                    : const Color(0xFFFF3D71).withOpacity(0.2))),
              child: Row(children: [
                Icon(_result! ? Icons.check_circle_rounded : Icons.error_rounded,
                  color: _result! ? const Color(0xFF30D158) : const Color(0xFFFF3D71),
                  size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_resultMsg,
                  style: TextStyle(
                    fontSize: 12,
                    color: _result! ? const Color(0xFF30D158) : const Color(0xFFFF3D71)))),
              ])),
            const SizedBox(height: 12),
          ] else if (_selectedSsid.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1A2840))),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.wifi_rounded,
                    color: Color(0xFF00D4FF), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_selectedSsid,
                    style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w500, color: Colors.white))),
                  GestureDetector(
                    onTap: () => setState(() { _selectedSsid = ''; }),
                    child: const Icon(Icons.close_rounded,
                      color: Color(0xFF3D5068), size: 16)),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _pwdController,
                  obscureText: !_pwdVisible,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: const TextStyle(color: Color(0xFF3D5068), fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF0D1520),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1A2840))),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1A2840))),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFF00D4FF), width: 1.5)),
                    suffixIcon: GestureDetector(
                      onTap: () => setState(() { _pwdVisible = !_pwdVisible; }),
                      child: Icon(
                        _pwdVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: const Color(0xFF3D5068), size: 18))),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _sending ? null : _connect,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: _sending
                          ? const Color(0xFF1A2840)
                          : const Color(0xFF00D4FF),
                        borderRadius: BorderRadius.circular(10)),
                      child: Center(child: _sending
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                        : const Text('Connect',
                            style: TextStyle(fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white))))),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          if (_selectedSsid.isEmpty && _result == null) ...[
            Row(children: [
              const Text('Nearby Networks',
                style: TextStyle(fontSize: 11, color: Color(0xFF3D5068),
                  letterSpacing: 0.5)),
              const Spacer(),
              GestureDetector(
                onTap: _scanning ? null : _scan,
                child: Icon(_scanning ? Icons.hourglass_empty_rounded : Icons.refresh_rounded,
                  color: const Color(0xFF00D4FF), size: 16)),
            ]),
            const SizedBox(height: 8),
            if (_scanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF00D4FF))))
            else if (_networks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No networks found',
                  style: TextStyle(fontSize: 12, color: Color(0xFF3D5068)))))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _networks.length,
                  separatorBuilder: (_, __) => const Divider(
                    color: Color(0xFF1A2840), height: 1),
                  itemBuilder: (_, i) {
                    final n = _networks[i];
                    final ssid = n.ssid ?? '';
                    return GestureDetector(
                      onTap: () => _selectNetwork(ssid),
                      child: Container(
                        color: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 10),
                        child: Row(children: [
                          Icon(_signalIcon(n.level ?? -100),
                            color: const Color(0xFF00D4FF), size: 16),
                          const SizedBox(width: 10),
                          Expanded(child: Text(ssid,
                            style: const TextStyle(
                              fontSize: 13, color: Colors.white))),
                          Text('${n.level ?? '?'} dBm',
                            style: const TextStyle(
                              fontSize: 10, color: Color(0xFF3D5068))),
                        ]),
                      ),
                    );
                  },
                ),
              ),
          ],

        ]),
      ),
    );
  }
}
