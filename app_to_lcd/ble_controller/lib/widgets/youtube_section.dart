import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/board_event.dart';

class YouTubeSection extends StatefulWidget {
  final String? currentUrl;
  final List<HistoryItem> history;
  final bool enabled;
  final Function(String url, String title) onSend;

  const YouTubeSection({super.key, required this.currentUrl,
    required this.history, required this.enabled, required this.onSend});

  @override
  State<YouTubeSection> createState() => _YouTubeSectionState();
}

class _YouTubeSectionState extends State<YouTubeSection> {
  final _ctrl    = TextEditingController();
  bool _fetching = false;

  String? _extractId(String url) {
    for (final p in [
      RegExp(r'(?:v=)([A-Za-z0-9_-]{11})'),
      RegExp(r'(?:youtu\.be/)([A-Za-z0-9_-]{11})'),
      RegExp(r'(?:shorts/)([A-Za-z0-9_-]{11})'),
    ]) {
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
      final req     = await client.getUrl(uri).timeout(const Duration(seconds: 5));
      final res     = await req.close().timeout(const Duration(seconds: 5));
      final body    = await res.transform(utf8.decoder).join();
      client.close();
      return (jsonDecode(body) as Map<String, dynamic>)['title'] as String? ?? videoId;
    } catch (_) { return videoId; }
  }

  Future<void> _send() async {
    final url = _ctrl.text.trim();
    if (url.isEmpty) return;
    final id = _extractId(url);
    setState(() => _fetching = true);
    String title = '';
    if (id != null) title = await _fetchTitle(id);
    if (mounted) setState(() => _fetching = false);
    widget.onSend(url, title);
    _ctrl.clear();
  }

  void _showHistory() {
    if (widget.history.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E3048),
            borderRadius: BorderRadius.circular(2))),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Recent Videos', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white))),
        Flexible(child: ListView(shrinkWrap: true, children: [
          ...widget.history.take(15).map((item) {
            final display = item.title.isNotEmpty ? item.title : item.url;
            return ListTile(
              leading: const Icon(Icons.play_circle_outline,
                color: Color(0xFFFF3D71), size: 20),
              title: Text(display, style: const TextStyle(
                fontSize: 13, color: Colors.white),
                overflow: TextOverflow.ellipsis),
              subtitle: Text(item.time, style: const TextStyle(
                fontSize: 10, color: Color(0xFF4B6070))),
              onTap: widget.enabled ? () {
                widget.onSend(item.url, item.title);
                Navigator.pop(context);
              } : null,
            );
          }),
        ])),
        const SizedBox(height: 16),
      ]),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2A3A))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.play_circle_fill,
            color: Color(0xFFFF3D71), size: 16),
          const SizedBox(width: 8),
          const Text('YOUTUBE', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: Color(0xFF4A5568), letterSpacing: 1.5)),
          const Spacer(),
          if (widget.history.isNotEmpty)
            GestureDetector(
              onTap: _showHistory,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2A3A),
                  borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.history, color: Color(0xFF4A5568), size: 14),
                  const SizedBox(width: 4),
                  Text('${widget.history.length}', style: const TextStyle(
                    fontSize: 10, color: Color(0xFF4A5568))),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF080C14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E2A3A))),
              child: TextField(
                controller: _ctrl,
                enabled: widget.enabled && !_fetching,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: InputDecoration(
                  hintText: _fetching ? 'Fetching title...' : 'Paste YouTube URL...',
                  hintStyle: TextStyle(fontSize: 12,
                    color: Colors.white.withOpacity(0.2)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                  prefixIcon: const Icon(Icons.link,
                    color: Color(0xFF4A5568), size: 16)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.enabled && !_fetching ? _send : null,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: widget.enabled && !_fetching
                  ? const Color(0xFFFF3D71)
                  : const Color(0xFF1E2A3A),
                borderRadius: BorderRadius.circular(10)),
              child: _fetching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                : Icon(Icons.send_rounded,
                    color: widget.enabled
                      ? Colors.white : const Color(0xFF4A5568),
                    size: 18)),
          ),
        ]),
      ]),
    );
  }
}
