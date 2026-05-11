import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/board_event.dart';
import '../services/watch_later_service.dart';
import '../services/ble_service.dart';
import '../services/board_state.dart';

class WatchLaterScreen extends StatelessWidget {
  const WatchLaterScreen({super.key});

  static const _bg     = Color(0xFF000000);
  static const _card   = Color(0xFF1C1C1E);
  static const _card2  = Color(0xFF2C2C2E);
  static const _border = Color(0xFF3A3A3C);
  static const _blue   = Color(0xFF0A84FF);
  static const _red    = Color(0xFFFF453A);
  static const _amber  = Color(0xFFFF9F0A);
  static const _label  = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    final wl        = context.watch<WatchLaterService>();
    final ble       = context.watch<BleService>();
    final connected = ble.state == ConnState.connected;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 17, color: _blue),
          onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Watch Later', style: TextStyle(
            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          Text('${wl.items.length} video${wl.items.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 10, color: _label)),
        ]),
        actions: [
          if (wl.pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _amber.withOpacity(0.4))),
                child: Text('${wl.pendingCount} pending',
                  style: const TextStyle(fontSize: 11,
                    color: _amber, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      body: wl.items.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bookmark_outline, color: _label.withOpacity(0.3), size: 48),
            const SizedBox(height: 12),
            const Text('Nothing saved yet', style: TextStyle(
              fontSize: 16, color: _label)),
            const SizedBox(height: 6),
            const Text('Share YouTube videos to save them here',
              style: TextStyle(fontSize: 12, color: Color(0xFF48484A))),
          ]))
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: wl.items.length,
            physics: const ClampingScrollPhysics(),
            itemBuilder: (_, i) {
              final item      = wl.items[i];
              final isPending = wl.pending.any((p) => p.url == item.url);
              return _WatchLaterTile(
                item:        item,
                isPending:   isPending,
                connected:   connected,
                onPlay: () {
                  context.read<BleService>().sendUrlWithTitle(item.url, item.title);
                  context.read<BoardState>().nowPlaying = item.title.isNotEmpty
                    ? item.title : item.url;
                  context.read<BoardState>().notifyListeners();
                  Navigator.pop(context);
                },
                onDelete: () {
                  final ble       = context.read<BleService>();
                  final connected = ble.state == ConnState.connected;
                  context.read<WatchLaterService>().removeItem(
                    item.url, boardConnected: connected);
                  if (connected) ble.watchLaterRemove(item.url);
                },
                onAddToSchedule: () => _addToSchedule(context, item),
              );
            },
          ),
    );
  }

  void _addToSchedule(BuildContext context, WatchLaterItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _SchedulePicker(item: item),
    );
  }
}

class _WatchLaterTile extends StatelessWidget {
  final WatchLaterItem item;
  final bool isPending;
  final bool connected;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onAddToSchedule;

  const _WatchLaterTile({
    required this.item, required this.isPending, required this.connected,
    required this.onPlay, required this.onDelete, required this.onAddToSchedule});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPending
            ? const Color(0xFFFF9F0A).withOpacity(0.3)
            : const Color(0xFF3A3A3C))),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFF3D71).withOpacity(0.10),
                borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.play_circle_outline,
                color: Color(0xFFFF3D71), size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(item.title.isNotEmpty ? item.title : item.videoId,
                style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w600, color: Colors.white),
                overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(children: [
                Text(item.addedAt, style: const TextStyle(
                  fontSize: 11, color: Color(0xFF8E8E93))),
                if (isPending) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9F0A).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4)),
                    child: const Text('PENDING', style: TextStyle(
                      fontSize: 8, color: Color(0xFFFF9F0A),
                      fontWeight: FontWeight.w700))),
                ],
              ]),
            ])),
          ]),
        ),
        Container(height: 0.5, color: const Color(0xFF3A3A3C)),
        Row(children: [
          if (connected)
            Expanded(child: _actionBtn(
              Icons.play_arrow_rounded, 'Play Now',
              const Color(0xFF0A84FF), onPlay)),
          Expanded(child: _actionBtn(
            Icons.calendar_month_rounded, 'Schedule',
            const Color(0xFFFF9F0A), onAddToSchedule)),
          Expanded(child: _actionBtn(
            Icons.delete_outline_rounded, 'Remove',
            const Color(0xFFFF453A), onDelete)),
        ]),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, String label,
      Color color, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(
            fontSize: 9, color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
}

class _SchedulePicker extends StatefulWidget {
  final WatchLaterItem item;
  const _SchedulePicker({required this.item});
  @override
  State<_SchedulePicker> createState() => _SchedulePickerState();
}

class _SchedulePickerState extends State<_SchedulePicker> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final board = context.read<BoardState>();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF3A3A3C),
            borderRadius: BorderRadius.circular(2))),
        const Text('Add to Schedule', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 4),
        Text(widget.item.title.isNotEmpty ? widget.item.title : widget.item.videoId,
          style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
          overflow: TextOverflow.ellipsis),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 180)),
              builder: (ctx, child) => Theme(
                data: ThemeData.dark(),
                child: child!));
            if (picked != null) setState(() => _selectedDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.calendar_today,
                color: Color(0xFFFF9F0A), size: 18),
              const SizedBox(width: 12),
              Text(
                '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                style: const TextStyle(fontSize: 16,
                  color: Colors.white, fontWeight: FontWeight.w600)),
              const Spacer(),
              const Text('Tap to change',
                style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            // find or create entry for selected date
            final entries  = List.from(board.scheduleEntries);
            final existing = entries.cast<dynamic>().where((e) =>
              e.date.year  == _selectedDate.year &&
              e.date.month == _selectedDate.month &&
              e.date.day   == _selectedDate.day).firstOrNull;
            final newItem  = QueueItem(
              videoId: widget.item.videoId,
              title:   widget.item.title,
              url:     widget.item.url);
            if (existing != null) {
              existing.playlist.add(newItem);
            } else {
              entries.add(ScheduleEntry(
                date:     _selectedDate,
                playlist: [newItem]));
            }
            board.scheduleEntries = List.from(entries);
            board.notifyListeners();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF1C1C1E),
                content: Text(
                  'Added to ${_selectedDate.day}/${_selectedDate.month}',
                  style: const TextStyle(color: Colors.white))));
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9F0A),
              borderRadius: BorderRadius.circular(12)),
            child: const Text('Add to This Date',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.black,
                fontWeight: FontWeight.w700))),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
