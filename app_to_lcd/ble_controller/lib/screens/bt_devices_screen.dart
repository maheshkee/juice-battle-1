import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/board_state.dart';
import '../services/bt_audio_service.dart';

class BtDevicesScreen extends StatefulWidget {
  const BtDevicesScreen({super.key});

  @override
  State<BtDevicesScreen> createState() => _BtDevicesScreenState();
}

class _BtDevicesScreenState extends State<BtDevicesScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble     = context.read<BleService>();
      final board   = context.read<BoardState>();
      final btAudio = context.read<BtAudioService>();
      if (ble.state == ConnState.connected) {
        btAudio.clearDevices();
        // Immediately show currently connected device if any
        if (board.btAudioStatus == 'connected' && board.btAudioDevice.isNotEmpty) {
          btAudio.setConnected(board.btAudioDevice, board.btAudioName);
        }
        ble.btList();
        ble.scanStart();
        btAudio.startScan();
      }
    });
  }

  @override
  void dispose() {
    context.read<BtAudioService>().stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble     = context.watch<BleService>();
    final board   = context.watch<BoardState>();
    final btAudio = context.watch<BtAudioService>();
    final connected = ble.state == ConnState.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF060B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF060B14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
            size: 17, color: Color(0xFF00D4FF)),
          onPressed: () => Navigator.pop(context)),
        title: const Row(children: [
          Icon(Icons.bluetooth, color: Color(0xFF00D4FF), size: 20),
          SizedBox(width: 10),
          Text('Bluetooth Devices', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF00D4FF), size: 20),
            onPressed: connected ? () {
              btAudio.clearDevices();
              ble.btList();
              ble.scanStart();
              btAudio.startScan();
            } : null),
        ],
      ),
      body: Column(children: [
        if (btAudio.scanning || board.scanning)
          const LinearProgressIndicator(
            color: Color(0xFF00D4FF),
            backgroundColor: Color(0xFF1A2840)),
        Expanded(child: _buildBody(ble, board, btAudio, connected)),
      ]),
    );
  }

  Widget _buildBody(BleService ble, BoardState board,
      BtAudioService btAudio, bool connected) {

    final isScanning = btAudio.scanning || board.scanning;

    // Merge board paired + phone scan, deduplicated by MAC
    final allDevices = List<BtAudioDevice>.from(btAudio.devices);

    // Connected device always at top — use board state as source of truth
    final isAudioConnected = board.btAudioStatus == 'connected' &&
        board.btAudioDevice.isNotEmpty;

    final connectedDevice = isAudioConnected
      ? (allDevices.where((d) => d.mac == board.btAudioDevice).firstOrNull
          ?? BtAudioDevice(
              mac:       board.btAudioDevice,
              name:      board.btAudioName.isNotEmpty
                           ? board.btAudioName : board.btAudioDevice,
              connected: true,
              paired:    true))
      : null;

    final otherDevices = allDevices
      .where((d) => d.mac != board.btAudioDevice)
      .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // SCAN BUTTON
        GestureDetector(
          onTap: connected ? () {
            if (isScanning) {
              ble.scanStop();
              btAudio.stopScan();
            } else {
              btAudio.clearDevices();
              ble.btList();
              ble.scanStart();
              btAudio.startScan();
            }
          } : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: connected
                ? const Color(0xFF00D4FF).withOpacity(0.10)
                : const Color(0xFF1E2A3A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: connected
                  ? const Color(0xFF00D4FF).withOpacity(0.4)
                  : const Color(0xFF1E2A3A))),
            child: Text(
              isScanning ? '⏹  STOP SCAN' : '🔍  SCAN ALL DEVICES',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: connected
                  ? const Color(0xFF00D4FF)
                  : const Color(0xFF4A5568)))),
        ),

        // CONNECTED DEVICE
        if (connectedDevice != null) ...[
          const SizedBox(height: 20),
          _sectionLabel('CONNECTED', const Color(0xFF34C759)),
          const SizedBox(height: 8),
          _connectedTile(connectedDevice, board, ble),
        ],

        // ALL OTHER DEVICES
        if (otherDevices.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel('AUDIO DEVICES', const Color(0xFFFF9F0A)),
          const SizedBox(height: 8),
          ...otherDevices.map((d) => _deviceTile(d, ble, connected)),
        ],

        if (!isScanning && allDevices.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: Text(
              'Tap SCAN ALL DEVICES to search',
              style: TextStyle(fontSize: 13, color: Color(0xFF4A5568))))),

        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _sectionLabel(String label, Color color) =>
    Text(label, style: TextStyle(
      fontSize: 9, fontWeight: FontWeight.w700,
      color: color.withOpacity(0.7), letterSpacing: 1.5));

  Widget _connectedTile(BtAudioDevice device, BoardState board, BleService ble) =>
    Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF34C759).withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF34C759).withOpacity(0.3))),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF34C759).withOpacity(0.15),
            borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.speaker_rounded,
            color: Color(0xFF34C759), size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(board.btAudioName.isNotEmpty
            ? board.btAudioName : device.mac,
            style: const TextStyle(
              fontSize: 14, color: Colors.white,
              fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(children: [
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Color(0xFF34C759))),
            const SizedBox(width: 5),
            const Text('Audio output active', style: TextStyle(
              fontSize: 11, color: Color(0xFF34C759))),
          ]),
          Text(device.mac, style: const TextStyle(
            fontSize: 9, color: Color(0xFF4A5568))),
        ])),
        GestureDetector(
          onTap: () => ble.btDisconnect(device.mac),
          child: _pill('DISCONNECT', const Color(0xFFFF3D71))),
      ]),
    );

  Widget _deviceTile(BtAudioDevice device, BleService ble, bool connected) =>
    Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1825),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: device.paired
            ? const Color(0xFF2A3F58)
            : const Color(0xFF1A2538))),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFFF9F0A).withOpacity(0.10),
            borderRadius: BorderRadius.circular(12)),
          child: Icon(
            device.paired
              ? Icons.speaker_rounded
              : Icons.speaker_outlined,
            color: device.paired
              ? const Color(0xFFFF9F0A)
              : const Color(0xFF4A6080),
            size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(device.name, style: const TextStyle(
            fontSize: 13, color: Colors.white,
            fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(children: [
            if (device.paired) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D4FF).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(4)),
                child: const Text('PAIRED', style: TextStyle(
                  fontSize: 8, color: Color(0xFF00D4FF),
                  fontWeight: FontWeight.w700))),
              const SizedBox(width: 6),
            ],
            Text(device.mac, style: const TextStyle(
              fontSize: 9, color: Color(0xFF4A5568))),
          ]),
        ])),
        const SizedBox(width: 8),
        if (device.connecting)
          const SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFF34C759)))
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: connected ? () {
                context.read<BtAudioService>().setConnecting(device.mac, true);
                ble.btConnect(device.mac);
              } : null,
              child: _pill('CONNECT', const Color(0xFF34C759))),
            if (device.paired) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: connected ? () => ble.btForget(device.mac) : null,
                child: _pill('FORGET', const Color(0xFFFF3D71))),
            ],
          ]),
      ]),
    );

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.35))),
    child: Text(label, style: TextStyle(
      fontSize: 10, fontWeight: FontWeight.w600, color: color)));
}
