import 'dart:async';
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
  Timer?              _connectTimer;
  String?             _connectingMac;
  StreamSubscription? _eventSub;
  String?             _expandedMac;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble     = context.read<BleService>();
      final btAudio = context.read<BtAudioService>();
      if (ble.state == ConnState.connected) {
        ble.btGetConnected();
        ble.btList();
        btAudio.startScan();
      }
      _eventSub = ble.events.listen((evt) {
        if (evt.event == 'bt_audio_connected' ||
            evt.event == 'bt_audio_error') {
          _cancelConnectTimer();
          if (mounted) setState(() {});
        }
      });
    });
  }

  @override
  void dispose() {
    _cancelConnectTimer();
    _eventSub?.cancel();
    context.read<BtAudioService>().stopScan();
    super.dispose();
  }

  void _startConnectTimer(String mac) {
    _cancelConnectTimer();
    _connectingMac = mac;
    _connectTimer  = Timer(const Duration(seconds: 35), () {
      if (mounted) {
        context.read<BtAudioService>().setConnecting(mac, false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection timed out — try again'),
            backgroundColor: Color(0xFF3A1A1A),
            duration: Duration(seconds: 3),
          ),
        );
        setState(() {});
      }
      _connectingMac = null;
    });
  }

  void _cancelConnectTimer() {
    _connectTimer?.cancel();
    _connectTimer  = null;
    _connectingMac = null;
  }

  @override
  Widget build(BuildContext context) {
    final ble       = context.watch<BleService>();
    final board     = context.watch<BoardState>();
    final btAudio   = context.watch<BtAudioService>();
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
              btAudio.clearDevicesKeepConnected(
                board.btAudioDevice, board.btAudioName);
              ble.btGetConnected();
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

    final isScanning     = btAudio.scanning || board.scanning;
    final isAudioConnected = board.btAudioStatus == 'connected' &&
        board.btAudioDevice.isNotEmpty;

    BtAudioDevice? connectedDevice;
    if (isAudioConnected) {
      connectedDevice = BtAudioDevice(
        mac:       board.btAudioDevice,
        name:      board.btAudioName.isNotEmpty
                     ? board.btAudioName : board.btAudioDevice,
        connected: true,
        paired:    true,
      );
    }

    final otherDevices = btAudio.devices
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
              btAudio.clearDevicesKeepConnected(
                board.btAudioDevice, board.btAudioName);
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

        // OTHER DEVICES
        if (otherDevices.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel('AUDIO DEVICES', const Color(0xFFFF9F0A)),
          const SizedBox(height: 8),
          ...otherDevices.map((d) => _deviceTile(d, ble, connected)),
        ],

        if (!isScanning && otherDevices.isEmpty && connectedDevice == null)
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

  Widget _connectedTile(BtAudioDevice device,
      BoardState board, BleService ble) {
    final isExpanded = _expandedMac == device.mac;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF34C759).withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF34C759).withOpacity(0.3))),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() =>
            _expandedMac = isExpanded ? null : device.mac),
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                  style: const TextStyle(fontSize: 14, color: Colors.white,
                    fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Color(0xFF34C759))),
                  const SizedBox(width: 5),
                  const Text('Audio output active', style: TextStyle(
                    fontSize: 11, color: Color(0xFF34C759))),
                ]),
                Text(device.mac, style: const TextStyle(
                  fontSize: 9, color: Color(0xFF4A5568))),
              ])),
              Icon(
                isExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
                color: const Color(0xFF34C759), size: 18),
            ]),
          ),
        ),
        if (isExpanded) ...[
          Container(height: 0.5,
            color: const Color(0xFF34C759).withOpacity(0.2)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => ble.btDisconnect(device.mac),
                child: _actionBtn('DISCONNECT',
                  Icons.bluetooth_disabled_rounded,
                  const Color(0xFFFF3D71)))),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _deviceTile(BtAudioDevice device,
      BleService ble, bool connected) {
    final isExpanded = _expandedMac == device.mac;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1825),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: device.paired
            ? const Color(0xFF2A3F58)
            : const Color(0xFF1A2538))),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() =>
            _expandedMac = isExpanded ? null : device.mac),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9F0A).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12)),
                child: Icon(
                  device.paired
                    ? Icons.speaker_rounded : Icons.speaker_outlined,
                  color: device.paired
                    ? const Color(0xFFFF9F0A) : const Color(0xFF4A6080),
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
                const SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF34C759)))
              else ...[
                GestureDetector(
                  onTap: connected ? () {
                    context.read<BtAudioService>()
                      .setConnecting(device.mac, true);
                    _startConnectTimer(device.mac);
                    ble.btConnect(device.mac);
                  } : null,
                  child: _pill('CONNECT', const Color(0xFF34C759))),
                const SizedBox(width: 6),
                Icon(
                  isExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                  color: const Color(0xFF4A5568), size: 18),
              ],
            ]),
          ),
        ),
        if (isExpanded && device.paired) ...[
          Container(height: 0.5,
            color: const Color(0xFF2A3F58)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Row(children: [
              Expanded(child: GestureDetector(
                onTap: connected ? () {
                  setState(() => _expandedMac = null);
                  ble.btForget(device.mac);
                } : null,
                child: _actionBtn('FORGET DEVICE',
                  Icons.delete_outline_rounded,
                  const Color(0xFFFF3D71)))),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.35))),
    child: Text(label, style: TextStyle(
      fontSize: 10, fontWeight: FontWeight.w600, color: color)));

  Widget _actionBtn(String label, IconData icon, Color color) =>
    Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
}
