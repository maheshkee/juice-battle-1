import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/board_event.dart';

class ScheduleSection extends StatefulWidget {
  final Schedule schedule;
  final bool     enabled;
  final bool     inWindow;
  final Map<String, dynamic> nextWindow;
  final Function(Schedule) onSend;

  const ScheduleSection({
    super.key,
    required this.schedule,
    required this.enabled,
    required this.inWindow,
    required this.nextWindow,
    required this.onSend,
  });

  @override
  State<ScheduleSection> createState() => _ScheduleSectionState();
}

class _ScheduleSectionState extends State<ScheduleSection> {
  late bool _enabled;
  late List<TimeWindow> _weekday;
  late List<TimeWindow> _weekend;
  final List<QueueItem> _playlist = [];
  final _urlCtrl   = TextEditingController();
  final _titleCtrl = TextEditingController();
  bool _fetchingTitle = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ScheduleSection old) {
    super.didUpdateWidget(old);
    if (old.schedule != widget.schedule) _sync();
  }

  void _sync() {
    _enabled = widget.schedule.enabled;
    _weekday = List.from(widget.schedule.weekday);
    _weekend = List.from(widget.schedule.weekend);
    if (_playlist.isEmpty && widget.schedule.playlist.isNotEmpty) {
      _playlist.addAll(widget.schedule.playlist);
    }
  }

  void _send() {
    widget.onSend(Schedule(
      enabled:  _enabled,
      weekday:  _weekday,
      weekend:  _weekend,
      playlist: List.from(_playlist),
    ));
  }

  String? _extractVideoId(String url) {
    final patterns = [
      RegExp(r'(?:v=)([A-Za-z0-9_-]{11})'),
      RegExp(r'(?:youtu\.be/)([A-Za-z0-9_-]{11})'),
      RegExp(r'(?:shorts/)([A-Za-z0-9_-]{11})'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1);
    }
    return null;
  }

  Future<String> _fetchTitle(String videoId) async {
    try {
      final client  = HttpClient();
      final uri     = Uri.parse(
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json');
      final request  = await client.getUrl(uri).timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(const Duration(seconds: 5));
      final body     = await response.transform(utf8.decoder).join();
      client.close();
      final decoded  = jsonDecode(body) as Map<String, dynamic>;
      return decoded['title'] as String? ?? videoId;
    } catch (_) {
      return videoId;
    }
  }

  Future<void> _addItem() async {
    final url         = _urlCtrl.text.trim();
    final manualTitle = _titleCtrl.text.trim();
    if (url.isEmpty) return;
    final videoId = _extractVideoId(url);
    if (videoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not a valid YouTube URL')));
      return;
    }
    String title = manualTitle;
    if (title.isEmpty) {
      setState(() => _fetchingTitle = true);
      title = await _fetchTitle(videoId);
      if (mounted) setState(() => _fetchingTitle = false);
    }
    if (mounted) setState(() {
      _playlist.add(QueueItem(videoId: videoId, title: title, url: url));
      _urlCtrl.clear();
      _titleCtrl.clear();
    });
  }

  Future<void> _pickTime(BuildContext context, String current,
      Function(String) onPicked) async {
    final parts = current.split(':');
    final init  = TimeOfDay(
      hour:   int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts[1]) ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: init);
    if (picked != null) {
      onPicked('${picked.hour.toString().padLeft(2,'0')}:'
               '${picked.minute.toString().padLeft(2,'0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFFFAB00);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0F1E),
        elevation: 0,
        title: const Text('Schedule',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          const Text('Enable', style: TextStyle(fontSize: 12, color: Color(0xFF4A5568))),
          Switch(
            value: _enabled,
            activeColor: color,
            onChanged: (v) => setState(() { _enabled = v; }),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // status
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: widget.inWindow
                ? const Color(0xFF00E5FF).withOpacity(0.08)
                : const Color(0xFF111827),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: widget.inWindow
                ? const Color(0xFF00E5FF).withOpacity(0.3)
                : const Color(0xFF1E2A3A)),
            ),
            child: Row(children: [
              Container(width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.inWindow
                    ? const Color(0xFF00E5FF) : const Color(0xFF4A5568),
                  boxShadow: widget.inWindow
                    ? [const BoxShadow(color: Color(0xFF00E5FF), blurRadius: 8)] : [],
                )),
              const SizedBox(width: 10),
              Expanded(child: Text(
                widget.inWindow
                  ? 'Within allowed hours — playlist playing'
                  : _nextWindowText(),
                style: TextStyle(fontSize: 12,
                  color: widget.inWindow
                    ? const Color(0xFF00E5FF) : const Color(0xFF4A5568)),
              )),
            ]),
          ),

          // playlist
          _sectionHeader('PLAYLIST'),
          const SizedBox(height: 10),
          TextField(
            controller: _urlCtrl,
            style: const TextStyle(fontSize: 12, color: Colors.white),
            decoration: _inputDec('Paste YouTube URL'),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(
              controller: _titleCtrl,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: _inputDec('Title (optional — auto-fetched from YouTube)'),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _fetchingTitle ? null : _addItem,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: _fetchingTitle
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2,
                        color: Color(0xFFFFAB00)))
                  : const Text('+ ADD', style: TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w700, color: color)),
              ),
            ),
          ]),
          const SizedBox(height: 10),

          if (_playlist.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E2A3A)),
              ),
              child: const Center(child: Text('No videos in schedule playlist',
                style: TextStyle(fontSize: 11, color: Color(0xFF4A5568)))),
            ),

          ..._playlist.asMap().entries.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E2A3A)),
            ),
            child: Row(children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(child: Text('${e.key + 1}',
                  style: const TextStyle(fontSize: 10, color: color,
                    fontWeight: FontWeight.w700))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.value.title,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    overflow: TextOverflow.ellipsis),
                  Text(e.value.url,
                    style: const TextStyle(fontSize: 9, color: Color(0xFF4A5568)),
                    overflow: TextOverflow.ellipsis),
                ])),
              GestureDetector(
                onTap: () => setState(() => _playlist.removeAt(e.key)),
                child: const Icon(Icons.delete_outline, color: Color(0xFFFF3D71), size: 18)),
            ]),
          )),

          const SizedBox(height: 24),

          // weekday
          _sectionHeader('WEEKDAYS'),
          const SizedBox(height: 10),
          _windowsList(_weekday, (u) => setState(() => _weekday = u)),

          const SizedBox(height: 24),

          // weekend
          _sectionHeader('WEEKENDS'),
          const SizedBox(height: 10),
          _windowsList(_weekend, (u) => setState(() => _weekend = u)),

          const SizedBox(height: 28),

          GestureDetector(
            onTap: widget.enabled ? _send : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: widget.enabled
                  ? const LinearGradient(
                      colors: [Color(0xFFFFAB00), Color(0xFFFF6D00)])
                  : null,
                color: widget.enabled ? null : const Color(0xFF1E2A3A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.enabled
                  ? 'SAVE & SEND TO BOARD'
                  : 'CONNECT BOARD TO SAVE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800,
                  color: widget.enabled ? Colors.black : const Color(0xFF4A5568),
                  letterSpacing: 1.5),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String label) => Row(children: [
    Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF4A5568),
      fontWeight: FontWeight.w700, letterSpacing: 2)),
    const SizedBox(width: 8),
    Expanded(child: Container(height: 1, color: const Color(0xFF1E2A3A))),
  ]);

  Widget _windowsList(List<TimeWindow> windows,
      Function(List<TimeWindow>) onChange) {
    return Column(children: [
      ...windows.asMap().entries.map((e) {
        final i = e.key;
        final w = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1E2A3A)),
          ),
          child: Row(children: [
            const Icon(Icons.access_time, color: Color(0xFF4A5568), size: 14),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _pickTime(context, w.start, (t) {
                final u = List<TimeWindow>.from(windows);
                u[i] = TimeWindow(start: t, end: w.end);
                onChange(u);
              }),
              child: _timePill(w.start),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('to', style: TextStyle(fontSize: 11,
                color: Color(0xFF4A5568)))),
            GestureDetector(
              onTap: () => _pickTime(context, w.end, (t) {
                final u = List<TimeWindow>.from(windows);
                u[i] = TimeWindow(start: w.start, end: t);
                onChange(u);
              }),
              child: _timePill(w.end),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                final u = List<TimeWindow>.from(windows)..removeAt(i);
                onChange(u);
              },
              child: const Icon(Icons.delete_outline,
                color: Color(0xFFFF3D71), size: 18)),
          ]),
        );
      }),
      const SizedBox(height: 4),
      GestureDetector(
        onTap: () {
          final u = List<TimeWindow>.from(windows)
            ..add(TimeWindow(start: '09:00', end: '17:00'));
          onChange(u);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1E2A3A)),
          ),
          child: const Text('+ Add Time Window', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF4A5568))),
        ),
      ),
    ]);
  }

  Widget _timePill(String time) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFFFAB00).withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFFFAB00).withOpacity(0.3)),
    ),
    child: Text(time, style: const TextStyle(fontSize: 14,
      fontWeight: FontWeight.w700, color: Color(0xFFFFAB00))),
  );

  InputDecoration _inputDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF4A5568)),
    filled: true,
    fillColor: const Color(0xFF1E2A3A),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF2D3748))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF2D3748))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFFFAB00))),
  );

  String _nextWindowText() {
    if (!_enabled) return 'Schedule disabled';
    final nw = widget.nextWindow;
    if (nw.isEmpty) return 'No upcoming windows set';
    final days  = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final day   = nw['day'] != null ? days[nw['day'] as int] : '';
    final start = nw['start'] ?? '';
    final end   = nw['end']   ?? '';
    return 'Next window: $day $start – $end';
  }
}
