import 'package:flutter/material.dart';
import '../models/board_event.dart';

class BleDevicesPanel extends StatefulWidget {
  final bool scanning;
  final List<ScannedDevice> scanResults;
  final List<ConnectedDevice> connectedDevices;
  final List<TrustedDevice> trustedDevices;
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
  bool _expanded = true;
  final Set<String> _expandedDevices = {};

  @override
  Widget build(BuildContext context) {
    final connectedMacs = widget.connectedDevices.map((d) => d.mac).toSet();
    final available = widget.scanResults
        .where((d) => !connectedMacs.contains(d.mac) && d.name.isNotEmpty && d.rssi >= -79)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.bluetooth,
                color: widget.scanning ? const Color(0xFF00E5FF) : const Color(0xFF4A5568), size: 18),
              const SizedBox(width: 8),
              const Text('BLE DEVICES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: Color(0xFF4A5568), letterSpacing: 1.5)),
              const SizedBox(width: 8),
              if (widget.connectedDevices.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${widget.connectedDevices.length} connected',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                      color: Color(0xFF00E676))),
                ),
              const Spacer(),
              if (widget.enabled)
                GestureDetector(
                  onTap: widget.scanning ? widget.onScanStop : widget.onScanStart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.scanning
                        ? const Color(0xFF00E5FF).withOpacity(0.15)
                        : const Color(0xFF1E2A3A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: widget.scanning
                        ? const Color(0xFF00E5FF).withOpacity(0.4)
                        : const Color(0xFF2A3A4A)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (widget.scanning)
                        const SizedBox(width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)))
                      else
                        const Icon(Icons.refresh, size: 14, color: Color(0xFF4A5568)),
                      const SizedBox(width: 4),
                      Text(widget.scanning ? 'STOP' : 'SCAN',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                          color: widget.scanning ? const Color(0xFF00E5FF) : const Color(0xFF4A5568))),
                    ]),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: const Color(0xFF4A5568), size: 20),
            ]),
          ),
        ),
        if (_expanded) ...[
          Container(height: 1, color: const Color(0xFF1E2A3A)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.connectedDevices.isNotEmpty) ...[
                const Text('CONNECTED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                  color: Color(0xFF4A5568), letterSpacing: 1)),
                const SizedBox(height: 6),
                ...widget.connectedDevices.map((d) => _connectedTile(d)),
                const SizedBox(height: 12),
              ],
              const Text('AVAILABLE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                color: Color(0xFF4A5568), letterSpacing: 1)),
              const SizedBox(height: 6),
              if (available.isEmpty)
                Center(child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    widget.scanning ? 'Scanning...'
                      : widget.enabled ? 'Tap SCAN to find devices'
                      : 'Connect to board first',
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.2)),
                  ),
                ))
              else
                ...available.map((d) => _availableTile(d)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _connectedTile(ConnectedDevice device) {
    final exp       = _expandedDevices.contains(device.mac);
    final isTrusted = widget.trustedDevices.any((t) => t.mac == device.mac);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF080C14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.2)),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => exp ? _expandedDevices.remove(device.mac) : _expandedDevices.add(device.mac)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Container(width: 8, height: 8,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00E676),
                  boxShadow: [BoxShadow(color: Color(0xFF00E676), blurRadius: 6)])),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(device.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                Text(device.mac, style: const TextStyle(fontSize: 9, color: Color(0xFF4A5568))),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('CONNECTED', style: TextStyle(fontSize: 8,
                  fontWeight: FontWeight.w600, color: Color(0xFF00E676))),
              ),
              const SizedBox(width: 6),
              Icon(exp ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: const Color(0xFF4A5568), size: 18),
            ]),
          ),
        ),
        if (exp) ...[
          Container(height: 1, color: const Color(0xFF1E2A3A)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _actionBtn('DISCONNECT', const Color(0xFFFF3D71),
                  () => widget.onDisconnect(device.mac))),
                const SizedBox(width: 8),
                Expanded(child: _actionBtn(
                  isTrusted ? 'FORGET' : 'TRUST',
                  isTrusted ? const Color(0xFF4A5568) : const Color(0xFF7C4DFF),
                  isTrusted ? () => widget.onForget(device.mac) : () {},
                )),
              ]),
              if (device.characteristics.where((c) => c.value.isNotEmpty).isNotEmpty) ...[
                const SizedBox(height: 10),
                ...device.characteristics.where((c) => c.value.isNotEmpty).map((c) =>
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Expanded(child: Text(c.name,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF4A5568)))),
                      Text(c.value, style: const TextStyle(fontSize: 10, color: Colors.white)),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _availableTile(ScannedDevice device) {
    final bars = device.rssi >= -65 ? 4 : device.rssi >= -72 ? 3 : device.rssi >= -79 ? 2 : 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF080C14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Row(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (i) => Container(
            width: 4, height: 4.0 + i * 3,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: i < bars ? const Color(0xFF00E5FF) : const Color(0xFF2A3A4A),
              borderRadius: BorderRadius.circular(1),
            ),
          )),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(device.name, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w500, color: Colors.white)),
          Text('${device.mac}  ${device.rssi} dBm',
            style: const TextStyle(fontSize: 9, color: Color(0xFF4A5568))),
        ])),
        if (widget.enabled)
          GestureDetector(
            onTap: () => widget.onConnect(device.mac),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
              ),
              child: const Text('CONNECT', style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w600, color: Color(0xFF00E5FF))),
            ),
          ),
      ]),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      ),
    );
  }
}
