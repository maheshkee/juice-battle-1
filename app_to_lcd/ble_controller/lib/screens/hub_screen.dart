import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/board_state.dart';
import '../widgets/connection_bar.dart';
import '../widgets/youtube_section.dart';
import '../widgets/player_controls.dart';
import '../widgets/ble_devices_panel.dart';
import '../widgets/log_console.dart';
import '../widgets/led_mode_bar.dart';

class HubScreen extends StatefulWidget {
  const HubScreen({super.key});
  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble   = context.read<BleService>();
      final board = context.read<BoardState>();
      _subs.add(ble.connState.listen((s) {
        setState(() {});
        if (s == ConnState.connected)    board.addLog('[APP] Connected to board');
        if (s == ConnState.disconnected) board.addLog('[APP] Disconnected');
      }));
      _subs.add(ble.devName.listen((_) => setState(() {})));
      _subs.add(ble.logs.listen((msg) => board.addLog(msg)));
      _subs.add(ble.events.listen((evt) => board.applyEvent(evt)));
    });
  }

  Future<void> _requestPermissions() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
  }

  @override
  void dispose() {
    for (var s in _subs) s.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble   = context.watch<BleService>();
    final board = context.watch<BoardState>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(ble),
            ConnectionBar(state: ble.state, onScan: () => ble.startScan(), onDisconnect: () => ble.disconnect()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  children: [
                    LedModeBar(
                      ledOn: board.ledOn, mode: board.mode,
                      enabled: ble.state == ConnState.connected,
                      onLedToggle: () => ble.sendLedToggle(),
                      onModeIdle:  () => ble.setModeIdle(),
                      onModeYT:    () => ble.setModeYouTube(),
                      onModeClock: () => ble.setModeClock(),
                    ),
                    const SizedBox(height: 12),
                    YouTubeSection(
                      currentUrl: board.currentUrl, history: board.urlHistory,
                      enabled: ble.state == ConnState.connected,
                      onSend: (url) => ble.sendUrl(url),
                    ),
                    const SizedBox(height: 12),
                    PlayerControls(
                      enabled:   ble.state == ConnState.connected,
                      onPause:   () => ble.playerPause(),
                      onResume:  () => ble.playerResume(),
                      onStop:    () => ble.playerStop(),
                      onMute:    () => ble.playerMute(),
                      onUnmute:  () => ble.playerUnmute(),
                    ),
                    const SizedBox(height: 12),
                    BleDevicesPanel(
                      scanning: board.scanning, scanResults: board.scanResults,
                      connectedDevices: board.connectedDevices, trustedDevices: board.trustedDevices,
                      enabled: ble.state == ConnState.connected,
                      onScanStart:  () => ble.scanStart(),
                      onScanStop:   () => ble.scanStop(),
                      onConnect:    (mac) => ble.connectDevice(mac),
                      onDisconnect: (mac) => ble.disconnectDevice(mac),
                      onForget:     (mac) => ble.forgetDevice(mac),
                    ),
                    const SizedBox(height: 12),
                    LogConsole(logs: board.logs, onClear: () { board.logs.clear(); board.notifyListeners(); }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BleService ble) {
    final live = ble.state == ConnState.connected;
    final c    = live ? const Color(0xFF00E5FF) : const Color(0xFFFF3D71);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF0052D4)]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.hub, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('BLE HUB', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 2)),
          Text('Arduino UNO Q', style: TextStyle(fontSize: 11, color: Color(0xFF4A5568), letterSpacing: 1)),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: c.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withOpacity(0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 7, height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c,
                boxShadow: [BoxShadow(color: c.withOpacity(0.6), blurRadius: 8)])),
            const SizedBox(width: 6),
            Text(live ? 'LIVE' : 'OFFLINE',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c, letterSpacing: 1)),
          ]),
        ),
      ]),
    );
  }
}
