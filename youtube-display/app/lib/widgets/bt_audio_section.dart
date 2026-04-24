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
  List<BtDevice> _scanResults  = [];
  List<BtDevice> _trusted      = [];
  bool           _scanning     = false;
  String?        _error;

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(widget.ble.btScanResults.listen((devices) {
      setState(() => _scanResults = devices);
    }));
    _subs.add(widget.ble.btTrusted.listen((devices) {
      setState(() => _trusted = devices);
    }));
    _subs.add(widget.ble.btScanning.listen((scanning) {
      setState(() => _scanning = scanning);
    }));
    _subs.add(widget.ble.btConnected.listen((device) {
      setState(() => _error = null);
    }));
    _subs.add(widget.ble.btError.listen((msg) {
      setState(() => _error = msg);
    }));
  }

  @override
  void dispose() {
    for (var s in _subs) s.cancel();
    super.dispose();
  }

  Set<String> get _trustedMacs => _trusted.map((d) => d.mac).toSet();

  // Available = found in scan but not already trusted
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
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A5568),
              letterSpacing: 1.5,
            )),
          const Spacer(),
          // Scan button
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
                        strokeWidth: 2,
                        color: Color(0xFF00E5FF),
                      ))
                  else
                    const Icon(Icons.bluetooth_searching,
                      size: 14, color: Color(0xFF4A5568)),
                  const SizedBox(width: 4),
                  Text(_scanning ? 'STOP' : 'SCAN',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: _scanning
                        ? const Color(0xFF00E5FF)
                        : const Color(0xFF4A5568),
                    )),
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
            child: Text(_error!,
              style: const TextStyle(fontSize: 10, color: Color(0xFFFF3D71))),
          ),
        ],

        // ── Paired speakers ───────────────────────────────────────────────────
        if (_trusted.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('PAIRED',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A5568),
              letterSpacing: 1,
            )),
          const SizedBox(height: 6),
          ..._trusted.map((d) => _pairedTile(d)),
        ],

        // ── Available speakers ────────────────────────────────────────────────
        if (_available.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('AVAILABLE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A5568),
              letterSpacing: 1,
            )),
          const SizedBox(height: 6),
          ..._available.map((d) => _availableTile(d)),
        ],

        // ── Empty state ───────────────────────────────────────────────────────
        if (_trusted.isEmpty && _available.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                widget.enabled
                  ? 'Tap SCAN to find Bluetooth speakers'
                  : 'Connect to board first',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.2),
                ),
              ),
            ),
          ),

      ]),
    );
  }

  // ── Paired device tile ────────────────────────────────────────────────────

  Widget _pairedTile(BtDevice device) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF080C14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF00E676),
            boxShadow: [BoxShadow(color: Color(0xFF00E676), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              )),
            Text(device.mac,
              style: const TextStyle(fontSize: 9, color: Color(0xFF4A5568))),
          ],
        )),
        // Connect button
        if (widget.enabled)
          GestureDetector(
            onTap: () => widget.ble.btConnect(device.mac),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF00E676).withOpacity(0.4)),
              ),
              child: const Text('CONNECT',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF00E676),
                )),
            ),
          ),
        // Forget button
        if (widget.enabled)
          GestureDetector(
            onTap: () => widget.ble.btForget(device.mac),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3D71).withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFFF3D71).withOpacity(0.3)),
              ),
              child: const Text('FORGET',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFF3D71),
                )),
            ),
          ),
      ]),
    );
  }

  // ── Available device tile ─────────────────────────────────────────────────

  Widget _availableTile(BtDevice device) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF080C14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Row(children: [
        const Icon(Icons.speaker_rounded,
          color: Color(0xFF4A5568), size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              )),
            Text(device.mac,
              style: const TextStyle(fontSize: 9, color: Color(0xFF4A5568))),
          ],
        )),
        if (widget.enabled)
          GestureDetector(
            onTap: () => widget.ble.btPair(device.mac),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withOpacity(0.4)),
              ),
              child: const Text('PAIR',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF00E5FF),
                )),
            ),
          ),
      ]),
    );
  }
}
