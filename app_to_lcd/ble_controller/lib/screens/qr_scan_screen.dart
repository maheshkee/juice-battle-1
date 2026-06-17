import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../services/board_state.dart';
import '../services/ble_service.dart';
import 'hub_screen.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _processing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    if (!raw.startsWith('BLE-Hub')) return;
    setState(() { _processing = true; });
    await _ctrl.stop();
    if (!mounted) return;
    final board = context.read<BoardState>();
    final ble   = context.read<BleService>();
    await board.saveBoardName(raw);
    ble.setTargetName(raw);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HubScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 48),
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF00D4FF), Color(0xFF0052D4)]),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.hub_rounded, color: Colors.white, size: 22)),
          const SizedBox(height: 16),
          const Text('BLE HUB', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w900,
            color: Colors.white, letterSpacing: 1.5)),
          const SizedBox(height: 6),
          const Text('Scan the QR code on your board',
            style: TextStyle(fontSize: 13, color: Color(0xFF3D5068))),
          const SizedBox(height: 32),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(children: [
                  MobileScanner(
                    controller: _ctrl,
                    onDetect: _onDetect,
                  ),
                  // corner frame overlay
                  Positioned.fill(child: CustomPaint(
                    painter: _ScanFramePainter())),
                  if (_processing)
                    Container(
                      color: Colors.black54,
                      child: const Center(child: CircularProgressIndicator(
                        color: Color(0xFF00D4FF)))),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1520),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1A2840))),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded,
                  color: Color(0xFF3D5068), size: 16),
                SizedBox(width: 10),
                Expanded(child: Text(
                  'Find the QR code sticker on your Arduino UNO Q board',
                  style: TextStyle(fontSize: 11, color: Color(0xFF3D5068)))),
              ])),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00D4FF)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    const len = 28.0;
    final r = Rect.fromLTWH(0, 0, size.width, size.height);
    // top-left
    canvas.drawLine(r.topLeft, r.topLeft + const Offset(len, 0), paint);
    canvas.drawLine(r.topLeft, r.topLeft + const Offset(0, len), paint);
    // top-right
    canvas.drawLine(r.topRight, r.topRight + const Offset(-len, 0), paint);
    canvas.drawLine(r.topRight, r.topRight + const Offset(0, len), paint);
    // bottom-left
    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(len, 0), paint);
    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(0, -len), paint);
    // bottom-right
    canvas.drawLine(r.bottomRight, r.bottomRight + const Offset(-len, 0), paint);
    canvas.drawLine(r.bottomRight, r.bottomRight + const Offset(0, -len), paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
