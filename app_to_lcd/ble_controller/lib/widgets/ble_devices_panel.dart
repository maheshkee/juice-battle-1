import 'package:flutter/material.dart';
import '../services/bt_audio_service.dart';

class BleDevicesPanel extends StatelessWidget {
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
  final BtAudioService btAudio;
  final String btAudioStatus;
  final String btAudioDevice;
  final String btAudioName;
  final Function(String mac, String name) onBtConnect;
  final Function(String) onBtDisconnect;
  final Function(String) onBtForget;

  const BleDevicesPanel({super.key,
    required this.scanning,
    required this.scanResults,
    required this.connectedDevices,
    required this.trustedDevices,
    required this.enabled,
    required this.onScanStart,
    required this.onScanStop,
    required this.onConnect,
    required this.onDisconnect,
    required this.onForget,
    required this.btAudio,
    required this.btAudioStatus,
    required this.btAudioDevice,
    required this.btAudioName,
    required this.onBtConnect,
    required this.onBtDisconnect,
    required this.onBtForget,
  });

  @override
  Widget build(BuildContext context) {
    final connectedMacs = connectedDevices
        .map((d) => d['mac'] as String).toSet();
    final bleAvailable = scanResults
        .where((d) => !connectedMacs.contains(d['mac']) &&
            (d['name'] ?? '').isNotEmpty &&
            (d['rssi'] ?? -999) >= -79)
        .toList()
      ..sort((a, b) => (b['rssi'] ?? -999).compareTo(a['rssi'] ?? -999));

    final isScanning = scanning || btAudio.scanning;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Row(children: [
          Expanded(child: _btn(
            isScanning ? '⏹  STOP SCAN' : '🔍  SCAN ALL DEVICES',
            const Color(0xFF00E5FF),
            enabled ? () {
              if (isScanning) {
                onScanStop();
                btAudio.stopScan();
              } else {
                onScanStart();
                btAudio.startScan();
              }
            } : () {},
          )),
        ]),

        if (isScanning) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(
            color: Color(0xFF00E5FF),
            backgroundColor: Color(0xFF1E2A3A)),
        ],

        if (btAudioStatus == 'connected') ...[
          const SizedBox(height: 16),
          _sectionLabel('AUDIO', const Color(0xFF34C759)),
          const SizedBox(height: 6),
          _btConnectedTile(),
        ],

        if (connectedDevices.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionLabel('BLE CONNECTED', const Color(0xFF00E5FF)),
          const SizedBox(height: 6),
          ...connectedDevices.map((d) => _bleConnectedTile(d)),
        ],

        if (btAudio.devices.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionLabel('AUDIO DEVICES', const Color(0xFFFF9F0A)),
          const SizedBox(height: 6),
          ...btAudio.devices
            .where((d) => !(btAudioStatus == 'connected' && btAudioDevice == d.mac))
            .map((d) => _btAvailableTile(d)),
        ],

        if (bleAvailable.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionLabel('BLE AVAILABLE', const Color(0xFF00E5FF)),
          const SizedBox(height: 6),
          ...bleAvailable.map((d) => _bleAvailableTile(d)),
        ],

        if (!isScanning &&
            connectedDevices.isEmpty &&
            btAudio.devices.isEmpty &&
            bleAvailable.isEmpty &&
            btAudioStatus != 'connected')
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: Text('Tap SCAN ALL DEVICES to search',
              style: TextStyle(fontSize: 11, color: Color(0xFF4A5568))))),

        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _sectionLabel(String label, Color color) =>
    Text(label, style: TextStyle(
      fontSize: 9, fontWeight: FontWeight.w700,
      color: color.withOpacity(0.6), letterSpacing: 1.5));

  Widget _btConnectedTile() => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF34C759).withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF34C759).withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.speaker_rounded, color: Color(0xFF34C759), size: 18),
      const SizedBox(width: 10),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          btAudioName.isNotEmpty ? btAudioName : btAudioDevice,
          style: const TextStyle(
            fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis),
        const Text('Audio output active', style: TextStyle(
          fontSize: 10, color: Color(0xFF34C759))),
      ])),
      GestureDetector(
        onTap: () => onBtDisconnect(btAudioDevice),
        child: _pill('DISCONNECT', const Color(0xFFFF3D71))),
    ]),
  );

  Widget _btAvailableTile(BtAudioDevice device) {
    final isConnecting = device.connecting;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2236),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3548))),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFFF9F0A).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.speaker_rounded,
            color: Color(0xFFFF9F0A), size: 18)),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(device.name, style: const TextStyle(
            fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
          Text(device.mac, style: const TextStyle(
            fontSize: 9, color: Color(0xFF4A5568))),
        ])),
        const SizedBox(width: 8),
        if (isConnecting)
          const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFF34C759)))
        else
          GestureDetector(
            onTap: enabled ? () => onBtConnect(device.mac, device.name) : null,
            child: _pill('CONNECT', const Color(0xFF34C759))),
      ]),
    );
  }

  Widget _bleConnectedTile(Map<String, dynamic> device) {
    final mac       = device['mac'] as String;
    final name      = device['name'] as String? ?? mac;
    final isTrusted = trustedDevices.any((t) => t['mac'] == mac);
    final chars     = (device['characteristics'] as List? ?? []);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5FF).withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 7, height: 7,
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Color(0xFF00E5FF))),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(
            fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600))),
          GestureDetector(
            onTap: () => onDisconnect(mac),
            child: _pill('DISCONNECT', const Color(0xFFFF3D71))),
        ]),
        Text(mac, style: const TextStyle(
          fontSize: 9, color: Color(0xFF4A5568))),
        if (chars.isNotEmpty) ...[
          const SizedBox(height: 6),
          ...chars.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              Expanded(child: Text(c['name'] ?? c['uuid'] ?? '',
                style: const TextStyle(fontSize: 10, color: Colors.white54))),
              Text(c['value'] ?? '-',
                style: const TextStyle(fontSize: 10, color: Color(0xFF00E5FF))),
            ]))),
        ],
        if (isTrusted)
          GestureDetector(
            onTap: () => onForget(mac),
            child: const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Forget device', style: TextStyle(
                fontSize: 9, color: Color(0xFF4A5568),
                decoration: TextDecoration.underline)))),
      ]),
    );
  }

  Widget _bleAvailableTile(Map<String, dynamic> device) {
    final mac  = device['mac'] as String;
    final name = device['name'] as String? ?? mac;
    final rssi = device['rssi'] as int? ?? -100;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2A3A),
        borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        _signalIcon(rssi),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(name, style: const TextStyle(
            fontSize: 11, color: Colors.white70)),
          Text('$mac  $rssi dBm', style: const TextStyle(
            fontSize: 9, color: Color(0xFF4A5568))),
        ])),
        GestureDetector(
          onTap: enabled ? () => onConnect(mac) : null,
          child: _pill('CONNECT', const Color(0xFF00E5FF))),
      ]),
    );
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.3))),
    child: Text(label, style: TextStyle(fontSize: 9, color: color)));

  Widget _signalIcon(int rssi) {
    final color = rssi >= -65
      ? const Color(0xFF00E5FF)
      : rssi >= -75 ? const Color(0xFFFFAB00) : const Color(0xFFFF3D71);
    return Icon(Icons.signal_cellular_alt, color: color, size: 16);
  }

  Widget _btn(String label, Color color, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: enabled
            ? color.withOpacity(0.12) : const Color(0xFF1E2A3A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
              ? color.withOpacity(0.4) : const Color(0xFF1E2A3A))),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: enabled ? color : const Color(0xFF4A5568)))));
}
