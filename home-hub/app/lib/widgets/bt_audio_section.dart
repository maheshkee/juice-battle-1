import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class BtAudioSection extends StatefulWidget {
  final bool       enabled;
  final BleService ble;

  const BtAudioSection({
    super.key,
    required this.enabled,
    required this.ble,
  });

  @override
  State<BtAudioSection> createState() => _BtAudioSectionState();
}

class _BtAudioSectionState extends State<BtAudioSection> {
  List<BtDevice> _scanResults = [];
  List<BtDevice> _trusted     = [];
  bool           _scanning    = false;
  String?        _error;
  String?        _connecting; // MAC of device currently being connected

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    if (widget.enabled) { widget.ble.btList(); }
    _subs.add(widget.ble.btScanResults.listen((d) =>
        setState(() => _scanResults = d)));
    _subs.add(widget.ble.btTrusted.listen((d) =>
        setState(() { _trusted = d; _connecting = null; })));
    _subs.add(widget.ble.btScanning.listen((s) =>
        setState(() => _scanning = s)));
    _subs.add(widget.ble.btConnected.listen((_) =>
        setState(() { _error = null; _connecting = null; })));
    _subs.add(widget.ble.btDisconnected.listen((_) =>
        setState(() => _connecting = null)));

    _subs.add(widget.ble.btError.listen((msg) =>
        setState(() { _error = msg; _connecting = null; })));
  }

  @override
  void dispose() {
    if (widget.enabled) { widget.ble.btList(); }
    for (var s in _subs) s.cancel();
    super.dispose();
  }

  Set<String> get _trustedMacs => _trusted.map((d) => d.mac).toSet();

  List<BtDevice> get _available => _scanResults
      .where((d) => !_trustedMacs.contains(d.mac) && d.name.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ───────────────────────────────────────────────────────────
        Row(children: [
          Icon(Icons.speaker_rounded,
            color: _scanning
                ? const Color(0xFF00E5FF)
                : const Color(0xFF4A5568),
            size: 16),
          const SizedBox(width: 8),
          const Text('BT AUDIO',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: Color(0xFF4A5568), letterSpacing: 1.5)),
          const Spacer(),
          if (widget.enabled)
            GestureDetector(
              onTap: _scanning
                  ? () => widget.ble.btScanStop()
                  : () {
                      setState(() { _scanResults = []; _error = null; });
                      widget.ble.btScanStart();
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _scanning
                      ? const Color(0xFF00E5FF).withOpacity(0.15)
                      : const Color(0xFF1E2A3A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _scanning
                      ? const Color(0xFF00E5FF).withOpacity(0.4)
                      : const Color(0xFF2A3A4A)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_scanning)
                    const SizedBox(width: 12, height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF00E5FF)))
                  else
                    const Icon(Icons.bluetooth_searching,
                        size: 14, color: Color(0xFF4A5568)),
                  const SizedBox(width: 4),
                  Text(_scanning ? 'STOP' : 'SCAN',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                      color: _scanning
                          ? const Color(0xFF00E5FF)
                          : const Color(0xFF4A5568))),
                ]),
              ),
            ),
        ]),

        // ── Error ─────────────────────────────────────────────────────────────
        if (_error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF3D71).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF3D71).withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFFF3D71), size: 14),
              const SizedBox(width: 6),
              Expanded(child: Text(_error!,
                style: const TextStyle(fontSize: 10, color: Color(0xFFFF3D71)))),
              GestureDetector(
                onTap: () => setState(() => _error = null),
                child: const Icon(Icons.close,
                    color: Color(0xFFFF3D71), size: 14)),
            ]),
          ),
        ],

        // ── Paired/Trusted speakers ───────────────────────────────────────────
        if (_trusted.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('PAIRED',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
              color: Color(0xFF4A5568), letterSpacing: 1)),
          const SizedBox(height: 6),
          ..._trusted.map((d) => _pairedTile(d)),
        ],

        // ── Available devices from scan ────────────────────────────────────────
        if (_available.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('AVAILABLE',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
              color: Color(0xFF4A5568), letterSpacing: 1)),
          const SizedBox(height: 6),
          ..._available.map((d) => _availableTile(d)),
        ],

        // ── Empty state ───────────────────────────────────────────────────────
        if (_trusted.isEmpty && _available.isEmpty && !_scanning)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                widget.enabled
                    ? 'Tap SCAN to find Bluetooth speakers'
                    : 'Connect to board first',
                style: TextStyle(fontSize: 11,
                    color: Colors.white.withOpacity(0.2)),
              ),
            ),
          ),

        if (_scanning && _available.isEmpty && _trusted.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text('Scanning for nearby devices...',
                style: TextStyle(fontSize: 11,
                    color: Color(0xFF00E5FF))),
            ),
          ),
      ]),
    );
  }

  // ── Paired device tile ────────────────────────────────────────────────────

  Widget _pairedTile(BtDevice device) {
    final isConnected = device.connected;
    final isConnecting = _connecting == device.mac;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF080C14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF00E676).withOpacity(0.3)
              : const Color(0xFF1E2A3A)),
      ),
      child: Row(children: [
        // Status dot
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected
                ? const Color(0xFF00E676)
                : const Color(0xFF4A5568),
            boxShadow: isConnected
                ? [const BoxShadow(
                    color: Color(0xFF00E676), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 10),
        // Name + MAC
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device.name,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: isConnected ? Colors.white : const Color(0xFF9AA5B4))),
            Text(device.mac,
              style: const TextStyle(fontSize: 9, color: Color(0xFF4A5568))),
          ],
        )),
        // Action buttons
        if (widget.enabled) ...[
          if (isConnecting)
            const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF00E5FF)))
          else if (isConnected)
            GestureDetector(
              onTap: () {
                setState(() => _connecting = device.mac);
                widget.ble.btDisconnect(device.mac);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3D71).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFFFF3D71).withOpacity(0.4)),
                ),
                child: const Text('DISCONNECT',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                      color: Color(0xFFFF3D71))),
              ),
            )
          else
            GestureDetector(
              onTap: () {
                setState(() => _connecting = device.mac);
                widget.ble.btConnect(device.mac);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFF00E676).withOpacity(0.4)),
                ),
                child: const Text('CONNECT',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                      color: Color(0xFF00E676))),
              ),
            ),
          const SizedBox(width: 6),
          // Forget button
          GestureDetector(
            onTap: () => widget.ble.btForget(device.mac),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2A3A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.delete_outline,
                  color: Color(0xFF4A5568), size: 14),
            ),
          ),
        ],
      ]),
    );
  }

  // ── Available device tile ─────────────────────────────────────────────────

  Widget _availableTile(BtDevice device) {
    final isConnecting = _connecting == device.mac;
    final bars = device.rssi >= -60 ? 4
        : device.rssi >= -70 ? 3
        : device.rssi >= -80 ? 2 : 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF080C14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Row(children: [
        // Signal bars
        Row(crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (i) => Container(
            width: 3, height: 4.0 + i * 3,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: i < bars
                  ? const Color(0xFF00E5FF)
                  : const Color(0xFF2A3A4A),
              borderRadius: BorderRadius.circular(1),
            ),
          )),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device.name,
              style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w500, color: Colors.white)),
            Text(device.mac,
              style: const TextStyle(fontSize: 9, color: Color(0xFF4A5568))),
          ],
        )),
        if (widget.enabled)
          isConnecting
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF00E5FF)))
            : GestureDetector(
                onTap: () {
                  setState(() => _connecting = device.mac);
                  widget.ble.btPair(device.mac);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF00E5FF).withOpacity(0.4)),
                  ),
                  child: const Text('PAIR',
                    style: TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF00E5FF))),
                ),
              ),
      ]),
    );
  }
}
