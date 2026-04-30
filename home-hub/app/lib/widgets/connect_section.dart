import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class ConnectSection extends StatelessWidget {
  final ConnState    state;
  final VoidCallback onScan;
  final VoidCallback onDisconnect;

  const ConnectSection({
    super.key,
    required this.state,
    required this.onScan,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Row(children: [
        _dot(),
        const SizedBox(width: 12),
        Expanded(child: _label()),
        const SizedBox(width: 12),
        _button(),
      ]),
    );
  }

  Widget _dot() {
    Color c;
    switch (state) {
      case ConnState.connected:
        c = const Color(0xFF00E676);
        break;
      case ConnState.scanning:
      case ConnState.connecting:
        c = const Color(0xFFFFAB00);
        break;
      case ConnState.disconnected:
        c = const Color(0xFF4A5568);
        break;
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c,
        boxShadow: state == ConnState.connected
          ? [BoxShadow(color: c.withOpacity(0.6), blurRadius: 10)]
          : null,
      ),
    );
  }

  Widget _label() {
    String title, sub;
    switch (state) {
      case ConnState.connected:
        title = 'Board Connected';
        sub   = 'Arduino UNO Q — AQ2';
        break;
      case ConnState.scanning:
        title = 'Scanning...';
        sub   = 'Looking for board';
        break;
      case ConnState.connecting:
        title = 'Connecting...';
        sub   = 'Please wait';
        break;
      case ConnState.disconnected:
        title = 'Not Connected';
        sub   = 'Tap SCAN to find board';
        break;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        )),
      Text(sub,
        style: const TextStyle(fontSize: 10, color: Color(0xFF4A5568))),
    ]);
  }

  Widget _button() {
    if (state == ConnState.connected) {
      return _pill(
        label: 'DISCONNECT',
        color: const Color(0xFFFF3D71),
        onTap: onDisconnect,
      );
    }
    if (state == ConnState.scanning || state == ConnState.connecting) {
      return Container(
        width: 36,
        height: 36,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFAB00).withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFAB00).withOpacity(0.4)),
        ),
        child: const CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFFFFAB00),
        ),
      );
    }
    return _pill(
      label: 'SCAN',
      color: const Color(0xFF00E5FF),
      onTap: onScan,
    );
  }

  Widget _pill({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.8,
          )),
      ),
    );
  }
}
