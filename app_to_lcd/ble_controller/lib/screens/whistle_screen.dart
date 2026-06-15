import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/board_state.dart';

class WhistleScreen extends StatelessWidget {
  const WhistleScreen({super.key});

  static const _bg      = Color(0xFF000000);
  static const _card    = Color(0xFF0D1520);
  static const _border  = Color(0xFF1E3048);
  static const _cyan    = Color(0xFF00E5FF);
  static const _green   = Color(0xFF34C759);
  static const _red     = Color(0xFFFF3D71);
  static const _amber   = Color(0xFFFF9F0A);
  static const _label   = Color(0xFF4A5568);

  @override
  Widget build(BuildContext context) {
    final ble       = context.watch<BleService>();
    final board     = context.watch<BoardState>();
    final connected = ble.state == ConnState.connected;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 17, color: _cyan),
          onPressed: () => Navigator.pop(context)),
        title: const Row(children: [
          Text('📣', style: TextStyle(fontSize: 18)),
          SizedBox(width: 8),
          Text('Whistle Counter', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(children: [

          // -- Status indicator --
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: board.whistleActive
                ? _green.withOpacity(0.08)
                : _label.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: board.whistleActive
                  ? _green.withOpacity(0.3)
                  : _border)),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: board.whistleActive ? _green : _label,
                  boxShadow: board.whistleActive ? [
                    BoxShadow(color: _green.withOpacity(0.5), blurRadius: 6)
                  ] : [])),
              const SizedBox(width: 10),
              Text(
                board.whistleActive
                  ? 'Counting active — listening for whistles'
                  : 'Counting stopped',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: board.whistleActive ? _green : _label)),
            ]),
          ),

          const SizedBox(height: 32),

          // -- Count display --
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: board.whistleActive
                  ? _cyan.withOpacity(0.25)
                  : _border),
              boxShadow: board.whistleActive ? [
                BoxShadow(
                  color: _cyan.withOpacity(0.06),
                  blurRadius: 24, spreadRadius: 0)
              ] : []),
            child: Column(children: [
              Text(
                '${board.whistleCount}',
                style: TextStyle(
                  fontSize: 96,
                  fontWeight: FontWeight.w100,
                  color: board.whistleActive ? _cyan : Colors.white,
                  height: 1,
                  fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 8),
              Text(
                board.whistleCount == 1 ? 'whistle' : 'whistles',
                style: const TextStyle(
                  fontSize: 14, color: _label,
                  letterSpacing: 0.3)),
            ]),
          ),

          const SizedBox(height: 32),

          // -- Start / Stop --
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: connected ? () {
                if (board.whistleActive) {
                  ble.whistleStop();
                  board.whistleActive = false;
                  board.notifyListeners();
                } else {
                  ble.whistleStart();
                  board.whistleCount  = 0;
                  board.whistleActive = true;
                  board.notifyListeners();
                }
              } : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: connected
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: board.whistleActive
                          ? [_red.withOpacity(0.9), _red.withOpacity(0.6)]
                          : [_green.withOpacity(0.9), _green.withOpacity(0.6)])
                    : null,
                  color: connected ? null : _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: connected
                      ? Colors.transparent
                      : _border),
                  boxShadow: connected ? [
                    BoxShadow(
                      color: (board.whistleActive ? _red : _green)
                        .withOpacity(0.3),
                      blurRadius: 16, offset: const Offset(0, 4))
                  ] : []),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  Icon(
                    board.whistleActive
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                    size: 24,
                    color: connected ? Colors.white : _label),
                  const SizedBox(width: 8),
                  Text(
                    board.whistleActive ? 'STOP' : 'START',
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: connected ? Colors.white : _label)),
                ]),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // -- Reset --
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: connected ? () {
                ble.whistleReset();
                board.whistleCount = 0;
                board.notifyListeners();
              } : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: connected
                    ? _amber.withOpacity(0.08)
                    : _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: connected
                      ? _amber.withOpacity(0.35)
                      : _border)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  Icon(Icons.refresh_rounded, size: 18,
                    color: connected ? _amber : _label),
                  const SizedBox(width: 6),
                  Text('RESET COUNT',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: connected ? _amber : _label)),
                ]),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // -- Info card --
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              const Text('HOW IT WORKS', style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700,
                color: _label, letterSpacing: 1.5)),
              const SizedBox(height: 10),
              _infoRow(Icons.mic_rounded, _cyan,
                'Always listening via USB microphone'),
              const SizedBox(height: 8),
              _infoRow(Icons.equalizer_rounded, _cyan,
                '5 consecutive detections above 95% confidence = 1 whistle'),
              const SizedBox(height: 8),
              _infoRow(Icons.timer_rounded, _cyan,
                '4 second cooldown between counts'),
              const SizedBox(height: 8),
              _infoRow(Icons.play_arrow_rounded, _green,
                'Press START to begin counting'),
            ]),
          ),

          if (!connected) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _red.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _red.withOpacity(0.2))),
              child: Row(children: [
                const Icon(Icons.bluetooth_disabled_rounded,
                  color: _red, size: 16),
                const SizedBox(width: 10),
                const Expanded(child: Text(
                  'Connect to BLE-Hub to control the counter',
                  style: TextStyle(fontSize: 12, color: _red))),
              ]),
            ),
          ],

        ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, Color color, String text) =>
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(
        fontSize: 12, color: Color(0xFF8E8E93), height: 1.4))),
    ]);
}
