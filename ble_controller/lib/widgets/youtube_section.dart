import 'package:flutter/material.dart';
import '../models/board_event.dart';

class YouTubeSection extends StatefulWidget {
  final String? currentUrl;
  final List<HistoryItem> history;
  final bool enabled;
  final Function(String) onSend;

  const YouTubeSection({super.key, required this.currentUrl, required this.history,
    required this.enabled, required this.onSend});

  @override
  State<YouTubeSection> createState() => _YouTubeSectionState();
}

class _YouTubeSectionState extends State<YouTubeSection> {
  final _ctrl = TextEditingController();

  void _send() {
    final url = _ctrl.text.trim();
    if (url.isEmpty) return;
    widget.onSend(url);
    _ctrl.clear();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

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
        Row(children: [
          const Icon(Icons.play_circle_fill, color: Color(0xFFFF0000), size: 18),
          const SizedBox(width: 8),
          const Text('YOUTUBE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: Color(0xFF4A5568), letterSpacing: 1.5)),
          const Spacer(),
          if (widget.currentUrl != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF0000).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('NOW PLAYING', style: TextStyle(fontSize: 8,
                fontWeight: FontWeight.w600, color: Color(0xFFFF0000))),
            ),
        ]),
        if (widget.currentUrl != null) ...[
          const SizedBox(height: 8),
          Text(widget.currentUrl!, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.35))),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF080C14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E2A3A)),
              ),
              child: TextField(
                controller: _ctrl,
                enabled: widget.enabled,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Paste YouTube URL...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.2)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  prefixIcon: const Icon(Icons.link, color: Color(0xFF4A5568), size: 18),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.enabled ? _send : null,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: widget.enabled
                  ? const LinearGradient(colors: [Color(0xFFFF0000), Color(0xFFCC0000)])
                  : null,
                color: widget.enabled ? null : const Color(0xFF1E2A3A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.send_rounded,
                color: widget.enabled ? Colors.white : const Color(0xFF4A5568), size: 20),
            ),
          ),
        ]),
        if (widget.history.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('HISTORY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
            color: Color(0xFF4A5568), letterSpacing: 1)),
          const SizedBox(height: 6),
          ...widget.history.take(3).map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: GestureDetector(
              onTap: widget.enabled ? () => widget.onSend(item.url) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF080C14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.history, color: Color(0xFF4A5568), size: 14),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.url, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF4A5568)))),
                  Text(item.time, style: const TextStyle(fontSize: 9, color: Color(0xFF2A3A4A))),
                ]),
              ),
            ),
          )),
        ],
      ]),
    );
  }
}
