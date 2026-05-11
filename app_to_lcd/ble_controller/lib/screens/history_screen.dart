import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/board_state.dart';
import '../models/board_event.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const _bg    = Color(0xFF000000);
  static const _card  = Color(0xFF1C1C1E);
  static const _red   = Color(0xFFFF3D71);
  static const _label = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    final board     = context.watch<BoardState>();
    final ble       = context.watch<BleService>();
    final connected = ble.state == ConnState.connected;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
            size: 17, color: Color(0xFFFF3D71)),
          onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('History', style: TextStyle(
            color: Colors.white, fontSize: 17,
            fontWeight: FontWeight.w700)),
          Text('${board.urlHistory.length} video${board.urlHistory.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 10, color: _label)),
        ]),
        actions: [
          if (board.urlHistory.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClear(context, board),
              child: const Text('Clear All', style: TextStyle(
                fontSize: 12, color: Color(0xFFFF3D71),
                fontWeight: FontWeight.w600))),
        ],
      ),
      body: board.urlHistory.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.history, color: _label.withOpacity(0.3), size: 48),
            const SizedBox(height: 12),
            const Text('No history yet', style: TextStyle(
              fontSize: 16, color: _label)),
            const SizedBox(height: 6),
            const Text('Videos you play will appear here',
              style: TextStyle(fontSize: 12, color: Color(0xFF48484A))),
          ]))
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: board.urlHistory.length,
            physics: const ClampingScrollPhysics(),
            itemBuilder: (_, i) {
              final item = board.urlHistory[i];
              return _HistoryTile(
                item:      item,
                connected: connected,
                onPlay: () {
                  ble.sendUrlWithTitle(item.url, item.title);
                  board.nowPlaying = item.title.isNotEmpty
                    ? item.title : item.url;
                  board.notifyListeners();
                  Navigator.pop(context);
                },
              );
            },
          ),
    );
  }

  void _confirmClear(BuildContext context, BoardState board) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3C),
              borderRadius: BorderRadius.circular(2))),
          const Text('Clear History?', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('This will remove all played videos from history.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              board.clearHistoryLocally();
              final ble = context.read<BleService>();
              if (ble.state == ConnState.connected) {
                ble.historyClear();
              }
              Navigator.pop(context);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3D71),
                borderRadius: BorderRadius.circular(12)),
              child: const Text('Clear All',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.white,
                  fontWeight: FontWeight.w700)))),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(12)),
              child: const Text('Cancel',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.white,
                  fontWeight: FontWeight.w600)))),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryItem item;
  final bool connected;
  final VoidCallback onPlay;

  const _HistoryTile({
    required this.item,
    required this.connected,
    required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final display = item.title.isNotEmpty ? item.title : item.url;
    return GestureDetector(
      onTap: connected ? onPlay : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF3A3A3C))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFF3D71).withOpacity(0.10),
                borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.play_circle_outline,
                color: connected
                  ? const Color(0xFFFF3D71)
                  : const Color(0xFF4A5568),
                size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(display, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: Colors.white),
                overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(item.time, style: const TextStyle(
                fontSize: 11, color: Color(0xFF8E8E93))),
            ])),
            if (connected)
              const Icon(Icons.play_arrow_rounded,
                color: Color(0xFF0A84FF), size: 20),
          ]),
        ),
      ),
    );
  }
}
