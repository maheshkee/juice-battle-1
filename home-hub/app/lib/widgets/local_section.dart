import 'package:flutter/material.dart';
import '../services/board_state.dart';
import '../services/ble_service.dart';

class LocalSection extends StatefulWidget {
  final bool       enabled;
  final BoardState board;
  final BleService ble;

  const LocalSection({
    super.key,
    required this.enabled,
    required this.board,
    required this.ble,
  });

  @override
  State<LocalSection> createState() => _LocalSectionState();
}

class _LocalSectionState extends State<LocalSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final board   = widget.board;
    final files   = board.localFiles;
    final enabled = widget.enabled;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        GestureDetector(
          onTap: () {
            setState(() => _expanded = !_expanded);
            if (_expanded && enabled) widget.ble.localList();
          },
          child: Row(children: [
            const Icon(Icons.folder_open, color: Color(0xFFFF0000), size: 18),
            const SizedBox(width: 8),
            const Text('LOCAL VIDEOS',
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: Colors.white70, letterSpacing: 1.5,
              )),
            const Spacer(),
            if (files.isNotEmpty)
              Text('${files.length} files',
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
            const SizedBox(width: 8),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.white38, size: 18),
          ]),
        ),

        if (_expanded) ...[
          const SizedBox(height: 12),

          // USB Import button
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: enabled && !board.usbImporting
                    ? () => widget.ble.localUsbImport() : null,
                icon: board.usbImporting
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.usb, size: 16),
                label: Text(
                  board.usbImporting
                      ? 'IMPORTING ${board.usbProgress}%'
                      : 'IMPORT FROM USB',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D2D44),
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: enabled ? () => widget.ble.localList() : null,
              icon: const Icon(Icons.refresh, size: 18),
              color: Colors.white38,
              tooltip: 'Refresh file list',
            ),
          ]),

          if (files.isEmpty) ...[
            const SizedBox(height: 12),
            const Center(
              child: Text('No videos on board storage. Plug in USB drive and tap IMPORT.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 12))),
          ] else ...[
            const SizedBox(height: 8),
            const Divider(color: Colors.white12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: files.length,
              itemBuilder: (ctx, i) {
                final f = files[i];
                final isPlaying = board.localStatus == 'playing' &&
                                  board.localFilename == f.filename;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isPlaying ? Icons.play_circle : Icons.movie_outlined,
                    color: isPlaying ? const Color(0xFFFF0000) : Colors.white38,
                    size: 20,
                  ),
                  title: Text(f.title,
                    style: TextStyle(
                      fontSize: 12,
                      color: isPlaying ? Colors.white : Colors.white70,
                      fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis),
                  trailing: Text('${f.sizeMb} MB',
                    style: const TextStyle(color: Colors.white24, fontSize: 10)),
                  onTap: enabled ? () => widget.ble.localPlay(f.filename) : null,
                );
              },
            ),
          ],
        ],
      ]),
    );
  }
}

