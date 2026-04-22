import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class ConnectionBar extends StatelessWidget {
  final ConnState state;
  final VoidCallback onScan;
  final VoidCallback onDisconnect;
  const ConnectionBar({super.key, required this.state, required this.onScan, required this.onDisconnect});

  Color get _c {
    switch (state) {
      case ConnState.connected:    return const Color(0xFF00E676);
      case ConnState.connecting:   return const Color(0xFFFFAB00);
      case ConnState.scanning:     return const Color(0xFF00E5FF);
      case ConnState.disconnected: return const Color(0xFF4A5568);
    }
  }

  String get _label {
    switch (state) {
      case ConnState.connected:    return 'Connected to BLE-Hub';
      case ConnState.connecting:   return 'Connecting...';
      case ConnState.scanning:     return 'Scanning for BLE-Hub...';
      case ConnState.disconnected: return 'Tap Scan to connect to board';
    }
  }

  IconData get _icon {
    switch (state) {
      case ConnState.connected:    return Icons.bluetooth_connected;
      case ConnState.connecting:   return Icons.bluetooth_searching;
      case ConnState.scanning:     return Icons.bluetooth_searching;
      case ConnState.disconnected: return Icons.bluetooth_disabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _c.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(_icon, color: _c, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(_label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _c))),
        _buildBtn(),
      ]),
    );
  }

  Widget _buildBtn() {
    if (state == ConnState.connected)
      return _btn('Disconnect', const Color(0xFFFF3D71), onDisconnect);
    if (state == ConnState.scanning || state == ConnState.connecting)
      return const SizedBox(width: 20, height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)));
    return _btn('Scan', const Color(0xFF00E5FF), onScan);
  }

  Widget _btn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ),
    );
  }
}
