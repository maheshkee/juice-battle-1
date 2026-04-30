import 'package:flutter/material.dart';

class BleDevicesPanel extends StatefulWidget {
  final bool scanning;
  final List<Map<String, dynamic>> scanResults;
  final List<Map<String, dynamic>> connectedDevices;
  final List<Map<String, dynamic>> trustedDevices;
  final bool enabled;
  final VoidCallback onScanStart;
  final VoidCallback onScanStop;
  final Function(String) onConnect;
  final Function(String) onDisconnect;
  final Function(String) onForget;

  const BleDevicesPanel({super.key,
    required this.scanning, required this.scanResults,
    required this.connectedDevices, required this.trustedDevices,
    required this.enabled, required this.onScanStart, required this.onScanStop,
    required this.onConnect, required this.onDisconnect, required this.onForget});

  @override
  State<BleDevicesPanel> createState() => _BleDevicesPanelState();
}

class _BleDevicesPanelState extends State<BleDevicesPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final connectedMacs = widget.connectedDevices.map((d) => d['mac'] as String).toSet();
    final available = widget.scanResults
        .where((d) => !connectedMacs.contains(d['mac']) &&
            (d['name'] ?? '').isNotEmpty && (d['rssi'] ?? -999) >= -79)
        .toList()
      ..sort((a, b) => (b['rssi'] ?? -999).compareTo(a['rssi'] ?? -999));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(children: [
            const Icon(Icons.bluetooth, color: Color(0xFF00E5FF), size: 16),
            const SizedBox(width: 8),
            const Text('BLE DEVICES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: Color(0xFF00E5FF), letterSpacing: 1.5)),
            const Spacer(),
            if (widget.connectedDevices.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${widget.connectedDevices.length} connected',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF00E5FF))),
              ),
            const SizedBox(width: 8),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more,
              color: const Color(0xFF4A5568), size: 18),
          ]),
        ),
        if (_expanded) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _btn(
              widget.scanning ? '⏹ STOP SCAN' : '🔍 SCAN',
              const Color(0xFF00E5FF),
              () => widget.scanning ? widget.onScanStop() : widget.onScanStart(),
            )),
          ]),
          if (widget.connectedDevices.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('CONNECTED', style: TextStyle(fontSize: 9, color: Color(0xFF4A5568), letterSpacing: 1.5)),
            const SizedBox(height: 6),
            ...widget.connectedDevices.map((d) => _connectedTile(d)),
          ],
          if (available.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('AVAILABLE', style: TextStyle(fontSize: 9, color: Color(0xFF4A5568), letterSpacing: 1.5)),
            const SizedBox(height: 6),
            ...available.map((d) => _availableTile(d)),
          ],
          if (!widget.scanning && available.isEmpty && widget.connectedDevices.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No devices found. Tap SCAN to search.',
                style: TextStyle(fontSize: 11, color: Color(0xFF4A5568))),
            ),
        ],
      ]),
    );
  }

  Widget _connectedTile(Map<String, dynamic> device) {
    final mac  = device['mac'] as String;
    final name = device['name'] as String? ?? mac;
    final isTrusted = widget.trustedDevices.any((t) => t['mac'] == mac);
    final chars = (device['characteristics'] as List? ?? []);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5FF).withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 7, height: 7,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00E5FF))),
          const SizedBox(width: 8),
          Expanded(child: Text(name,
            style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600))),
          GestureDetector(
            onTap: () => widget.onDisconnect(mac),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3D71).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFF3D71).withOpacity(0.3)),
              ),
              child: const Text('DISCONNECT', style: TextStyle(fontSize: 9, color: Color(0xFFFF3D71))),
            ),
          ),
        ]),
        Text(mac, style: const TextStyle(fontSize: 9, color: Color(0xFF4A5568))),
        if (chars.isNotEmpty) ...[
          const SizedBox(height: 6),
          ...chars.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              Expanded(child: Text(c['name'] ?? c['uuid'] ?? '',
                style: const TextStyle(fontSize: 10, color: Colors.white54))),
              Text(c['value'] ?? '-',
                style: const TextStyle(fontSize: 10, color: Color(0xFF00E5FF))),
            ]),
          )),
        ],
        if (isTrusted)
          GestureDetector(
            onTap: () => widget.onForget(mac),
            child: const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Forget device', style: TextStyle(fontSize: 9, color: Color(0xFF4A5568),
                decoration: TextDecoration.underline)),
            ),
          ),
      ]),
    );
  }

  Widget _availableTile(Map<String, dynamic> device) {
    final mac  = device['mac'] as String;
    final name = device['name'] as String? ?? mac;
    final rssi = device['rssi'] as int? ?? -100;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2A3A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        _signalIcon(rssi),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          Text('$mac  $rssi dBm', style: const TextStyle(fontSize: 9, color: Color(0xFF4A5568))),
        ])),
        GestureDetector(
          onTap: widget.enabled ? () => widget.onConnect(mac) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
            ),
            child: const Text('CONNECT', style: TextStyle(fontSize: 9, color: Color(0xFF00E5FF))),
          ),
        ),
      ]),
    );
  }

  Widget _signalIcon(int rssi) {
    final color = rssi >= -65
      ? const Color(0xFF00E5FF)
      : rssi >= -75
        ? const Color(0xFFFFAB00)
        : const Color(0xFFFF3D71);
    return Icon(Icons.signal_cellular_alt, color: color, size: 16);
  }

  Widget _btn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: widget.enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: widget.enabled ? color.withOpacity(0.12) : const Color(0xFF1E2A3A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.enabled ? color.withOpacity(0.4) : const Color(0xFF1E2A3A)),
        ),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
            color: widget.enabled ? color : const Color(0xFF4A5568))),
      ),
    );
  }
}
