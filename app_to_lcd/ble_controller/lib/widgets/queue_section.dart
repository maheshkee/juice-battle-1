import 'package:flutter/material.dart';
import '../models/board_event.dart';

class QueueSection extends StatefulWidget {
  final QueueStatus status;
  final bool enabled;
  final Function(List<QueueItem>) onSendQueue;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onSkip;
  final VoidCallback onReplay;
  final VoidCallback onStop;
  final Function(int) onGoto;

  const QueueSection({
    super.key,
    required this.status,
    required this.enabled,
    required this.onSendQueue,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onSkip,
    required this.onReplay,
    required this.onStop,
    required this.onGoto,
  });

  @override
  State<QueueSection> createState() => _QueueSectionState();
}

class _QueueSectionState extends State<QueueSection> {
  final List<QueueItem> _localQueue = [];
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();

  void _addItem() {
    final url   = _urlController.text.trim();
    final title = _titleController.text.trim();
    if (url.isEmpty) return;
    final videoId = _extractVideoId(url);
    if (videoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not a valid YouTube URL')));
      return;
    }
    setState(() {
      _localQueue.add(QueueItem(
        videoId: videoId,
        title:   title.isEmpty ? videoId : title,
        url:     url,
      ));
      _urlController.clear();
      _titleController.clear();
    });
  }

  void _removeItem(int index) => setState(() => _localQueue.removeAt(index));

  void _sendQueue() {
    if (_localQueue.isEmpty) return;
    widget.onSendQueue(List.from(_localQueue));
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

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // header
        Row(children: [
          const Icon(Icons.queue_music, color: Color(0xFF7C4DFF), size: 16),
          const SizedBox(width: 8),
          const Text('QUEUE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: Color(0xFF7C4DFF), letterSpacing: 1.5)),
          const Spacer(),
          if (s.active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: s.paused
                  ? const Color(0xFFFFAB00).withOpacity(0.15)
                  : const Color(0xFF00E5FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: s.paused
                  ? const Color(0xFFFFAB00).withOpacity(0.4)
                  : const Color(0xFF00E5FF).withOpacity(0.4)),
              ),
              child: Text(
                s.paused ? 'PAUSED' : '▶ ${s.index + 1}/${s.total}',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                  color: s.paused ? const Color(0xFFFFAB00) : const Color(0xFF00E5FF)),
              ),
            ),
        ]),
        const SizedBox(height: 12),

        // now playing
        if (s.active && s.current != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.play_circle, color: Color(0xFF7C4DFF), size: 14),
              const SizedBox(width: 8),
              Expanded(child: Text(s.current!.title,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis)),
            ]),
          ),
          const SizedBox(height: 10),

          // queue controls
          Row(children: [
            _ctrl('⏮ REPLAY', const Color(0xFF00E5FF), widget.onReplay),
            const SizedBox(width: 6),
            _ctrl(s.paused ? '▶ RESUME' : '⏸ PAUSE',
              const Color(0xFFFFAB00),
              s.paused ? widget.onResume : widget.onPause),
            const SizedBox(width: 6),
            _ctrl('⏭ SKIP', const Color(0xFF00E5FF), widget.onSkip),
            const SizedBox(width: 6),
            _ctrl('⏹ STOP', const Color(0xFFFF3D71), widget.onStop),
          ]),
          const SizedBox(height: 12),
        ],

        // board queue list
        if (s.queue.isNotEmpty) ...[
          const Text('ON BOARD', style: TextStyle(fontSize: 9, color: Color(0xFF4A5568), letterSpacing: 1.5)),
          const SizedBox(height: 6),
          ...s.queue.asMap().entries.map((e) {
            final isCurrent = s.active && e.key == s.index;
            return GestureDetector(
              onTap: widget.enabled ? () => widget.onGoto(e.key) : null,
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isCurrent
                    ? const Color(0xFF7C4DFF).withOpacity(0.15)
                    : const Color(0xFF1E2A3A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isCurrent
                    ? const Color(0xFF7C4DFF).withOpacity(0.5)
                    : Colors.transparent),
                ),
                child: Row(children: [
                  Text('${e.key + 1}', style: const TextStyle(fontSize: 10, color: Color(0xFF4A5568))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.value.title,
                    style: TextStyle(fontSize: 11,
                      color: isCurrent ? const Color(0xFF7C4DFF) : Colors.white60),
                    overflow: TextOverflow.ellipsis)),
                  if (isCurrent)
                    const Icon(Icons.graphic_eq, color: Color(0xFF7C4DFF), size: 12),
                ]),
              ),
            );
          }),
          const SizedBox(height: 12),
        ],

        // add to local queue
        const Text('BUILD QUEUE', style: TextStyle(fontSize: 9, color: Color(0xFF4A5568), letterSpacing: 1.5)),
        const SizedBox(height: 6),
        TextField(
          controller: _urlController,
          style: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: _inputDec('YouTube URL'),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _titleController,
          style: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: _inputDec('Title (optional)'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _ctrl('+ ADD', const Color(0xFF7C4DFF), _addItem)),
          const SizedBox(width: 8),
          Expanded(child: _ctrl('CLEAR', const Color(0xFF4A5568),
            () => setState(() => _localQueue.clear()))),
        ]),

        if (_localQueue.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._localQueue.asMap().entries.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2A3A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Text('${e.key + 1}', style: const TextStyle(fontSize: 10, color: Color(0xFF4A5568))),
              const SizedBox(width: 8),
              Expanded(child: Text(e.value.title,
                style: const TextStyle(fontSize: 11, color: Colors.white60),
                overflow: TextOverflow.ellipsis)),
              GestureDetector(
                onTap: () => _removeItem(e.key),
                child: const Icon(Icons.close, color: Color(0xFFFF3D71), size: 14)),
            ]),
          )),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity,
            child: _ctrl('▶ SEND & PLAY', const Color(0xFF00E5FF), () {
              _sendQueue();
              Future.delayed(const Duration(milliseconds: 300), widget.onPlay);
            })),
        ],

      ]),
    );
  }

  Widget _ctrl(String label, Color color, VoidCallback onTap) {
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

  InputDecoration _inputDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF4A5568)),
    filled: true,
    fillColor: const Color(0xFF1E2A3A),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF2D3748))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF2D3748))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF7C4DFF))),
  );
}
