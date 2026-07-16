import 'package:flutter/material.dart';
import '../models/queue_item.dart';
import '../services/board_state.dart';

class QueueSection extends StatefulWidget {
  final bool      enabled;
  final BoardState board;
  final VoidCallback onSend;

  const QueueSection({
    super.key,
    required this.enabled,
    required this.board,
    required this.onSend,
  });

  @override
  State<QueueSection> createState() => _QueueSectionState();
}

class _QueueSectionState extends State<QueueSection> {
  bool _sent = false;
  final _urlCtrl   = TextEditingController();
  final _titleCtrl = TextEditingController();

  void _addItem() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    final title = _titleCtrl.text.trim();
    widget.board.addToQueue(QueueItem.fromUrl(url, title: title));
    _urlCtrl.clear();
    _titleCtrl.clear();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.board.pendingQueue;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          const Icon(Icons.queue_music, color: Color(0xFFFF0000), size: 18),
          const SizedBox(width: 8),
          const Text('VIDEO QUEUE',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: Colors.white70, letterSpacing: 1.5,
            )),
          const Spacer(),
          if (queue.isNotEmpty)
            TextButton(
              onPressed: widget.board.clearPendingQueue,
              child: const Text('CLEAR',
                style: TextStyle(fontSize: 10, color: Color(0xFFFF3D71))),
            ),
        ]),
        const SizedBox(height: 12),

        // URL input
        TextField(
          controller: _urlCtrl,
          enabled: widget.enabled,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: _inputDec('YouTube URL *'),
        ),
        const SizedBox(height: 8),

        // Title input (optional)
        TextField(
          controller: _titleCtrl,
          enabled: widget.enabled,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: _inputDec('Title (optional)'),
        ),
        const SizedBox(height: 10),

        // Add button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.enabled ? _addItem : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('ADD TO QUEUE', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF0000),
              side: const BorderSide(color: Color(0xFFFF0000)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),

        // Queue list
        if (queue.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(color: Colors.white12),
          const SizedBox(height: 4),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: queue.length,
            onReorder: widget.board.reorderQueue,
            itemBuilder: (ctx, i) {
              final item = queue[i];
              return ListTile(
                key: ValueKey(item.videoId + i.toString()),
                dense: true,
                leading: Text('${i+1}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
                title: Text(
                  item.title.isNotEmpty ? item.title : item.videoId,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.drag_handle, color: Colors.white24, size: 18),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => widget.board.removeFromQueue(i),
                    child: const Icon(Icons.close, color: Colors.white38, size: 16),
                  ),
                ]),
              );
            },
          ),
          const SizedBox(height: 10),

          // Send queue button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.enabled && queue.isNotEmpty && !_sent
                  ? () {
                      widget.onSend();
                      setState(() => _sent = true);
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _sent = false);
                      });
                    }
                  : null,
              icon: const Icon(Icons.send, size: 16),
              label: Text('SEND QUEUE (${queue.length} videos)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _sent ? const Color(0xFF2D6A2D) : const Color(0xFFFF0000),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
    filled: true,
    fillColor: Colors.white.withOpacity(0.05),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFFF0000)),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );
}
