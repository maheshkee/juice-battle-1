import 'package:flutter/material.dart';

class YouTubeSection extends StatefulWidget {
  final String?      currentUrl;
  final List<String> history;
  final bool         enabled;
  final Function(String) onSend;

  const YouTubeSection({
    super.key,
    required this.currentUrl,
    required this.history,
    required this.enabled,
    required this.onSend,
  });

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
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = widget.currentUrl != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: playing
            ? const Color(0xFFFF0000).withOpacity(0.3)
            : const Color(0xFF1E2A3A),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ──────────────────────────────────────────────────────────
        Row(children: [
          const Icon(Icons.play_circle_fill, color: Color(0xFFFF0000), size: 18),
          const SizedBox(width: 8),
          const Text('YOUTUBE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A5568),
              letterSpacing: 1.5,
            )),
          const Spacer(),
          if (playing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF0000).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFFF0000).withOpacity(0.3),
                ),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.fiber_manual_record,
                  color: Color(0xFFFF0000), size: 8),
                SizedBox(width: 4),
                Text('NOW PLAYING',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF0000),
                  )),
              ]),
            ),
        ]),

        // ── Now playing URL ──────────────────────────────────────────────────
        if (playing) ...[
          const SizedBox(height: 8),
          Text(
            widget.currentUrl!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
        ],

        const SizedBox(height: 14),

        // ── URL input + send ─────────────────────────────────────────────────
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
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.18),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  prefixIcon: const Icon(
                    Icons.link,
                    color: Color(0xFF4A5568),
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.enabled ? _send : null,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: widget.enabled
                  ? const LinearGradient(
                      colors: [Color(0xFFFF0000), Color(0xFF8B0000)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
                color: widget.enabled ? null : const Color(0xFF1E2A3A),
                borderRadius: BorderRadius.circular(12),
                boxShadow: widget.enabled
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFF0000).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
              ),
              child: Icon(
                Icons.send_rounded,
                color: widget.enabled ? Colors.white : const Color(0xFF4A5568),
                size: 20,
              ),
            ),
          ),
        ]),

        // ── History ──────────────────────────────────────────────────────────
        if (widget.history.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('RECENT',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A5568),
              letterSpacing: 1,
            )),
          const SizedBox(height: 6),
          ...widget.history.take(3).map((url) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: GestureDetector(
              onTap: widget.enabled ? () => widget.onSend(url) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF080C14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E2A3A)),
                ),
                child: Row(children: [
                  const Icon(Icons.history,
                    color: Color(0xFF4A5568), size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4A5568),
                      )),
                  ),
                  const Icon(Icons.play_arrow_rounded,
                    color: Color(0xFF2A3A4A), size: 16),
                ]),
              ),
            ),
          )),
        ],

      ]),
    );
  }
}
