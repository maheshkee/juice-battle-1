import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/board_state.dart';
import '../widgets/connect_section.dart';
import '../widgets/youtube_section.dart';
import '../widgets/player_controls.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
        if (s == ConnState.disconnected) board.clearCurrentUrl();
      }));
      _subs.add(ble.devName.listen((_) => setState(() {})));
      _subs.add(ble.logs.listen((msg) => board.addLog(msg)));
    });
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    // Small delay then re-check — Android sometimes needs a moment
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    for (var s in _subs) s.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble       = context.watch<BleService>();
    final board     = context.watch<BoardState>();
    final connected = ble.state == ConnState.connected;

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _buildHeader(ble),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(children: [
                ConnectSection(
                  state:        ble.state,
                  onScan:       () => ble.startScan(),
                  onDisconnect: () => ble.disconnect(),
                ),
                const SizedBox(height: 12),
                YouTubeSection(
                  currentUrl: board.currentUrl,
                  history:    board.urlHistory,
                  enabled:    connected,
                  onSend: (url) {
                    ble.sendUrl(url);
                    board.setCurrentUrl(url);
                  },
                ),
                const SizedBox(height: 12),
                PlayerControls(
                  enabled:   connected,
                  onPause:   () => ble.playerPause(),
                  onResume:  () => ble.playerResume(),
                  onStop: () {
                    ble.playerStop();
                    board.clearCurrentUrl();
                  },
                  onVolUp:   () => ble.playerVolUp(),
                  onVolDown: () => ble.playerVolDown(),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(BleService ble) {
    Color statusColor;
    String statusText;

    switch (ble.state) {
      case ConnState.connected:
        statusColor = const Color(0xFF00E676);
        statusText  = 'LIVE';
        break;
      case ConnState.scanning:
      case ConnState.connecting:
        statusColor = const Color(0xFFFFAB00);
        statusText  = ble.state == ConnState.scanning ? 'SCANNING' : 'CONNECTING';
        break;
      case ConnState.disconnected:
        statusColor = const Color(0xFFFF3D71);
        statusText  = 'OFFLINE';
        break;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF0000), Color(0xFF8B0000)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF0000).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('YT DISPLAY',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 2,
            )),
          Text('Arduino UNO Q',
            style: TextStyle(
              fontSize: 10,
              color: Color(0xFF4A5568),
              letterSpacing: 1,
            )),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withOpacity(0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withOpacity(0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(statusText,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: statusColor,
                letterSpacing: 1,
              )),
          ]),
        ),
      ]),
    );
  }
}
