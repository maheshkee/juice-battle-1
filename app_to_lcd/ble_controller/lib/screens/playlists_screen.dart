import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/board_event.dart';
import '../services/playlist_service.dart';
import '../services/watch_later_service.dart';
import '../services/ble_service.dart';

void _syncPlaylistsToBoard(BuildContext context) {
  final ble = context.read<BleService>();
  final pl  = context.read<PlaylistService>();
  if (ble.state == ConnState.connected) {
    ble.sendPlaylists(pl.toJsonList());
    pl.markClean();
  }
}


class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  static const _bg     = Color(0xFF000000);
  static const _card   = Color(0xFF1C1C1E);
  static const _border = Color(0xFF3A3A3C);
  static const _green  = Color(0xFF30D158);
  static const _label  = Color(0xFF8E8E93);
  static const _red    = Color(0xFFFF453A);

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PlaylistService>();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 17, color: _green),
          onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Playlists', style: TextStyle(
            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          Text('${ps.playlists.length} playlist${ps.playlists.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 10, color: _label)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: _green, size: 24),
            onPressed: () => _showCreateDialog(context, ps)),
        ],
      ),
      body: ps.playlists.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.queue_music, color: _label.withOpacity(0.3), size: 48),
            const SizedBox(height: 12),
            const Text('No playlists yet', style: TextStyle(
              fontSize: 16, color: _label)),
            const SizedBox(height: 6),
            const Text('Tap + to create one',
              style: TextStyle(fontSize: 12, color: Color(0xFF48484A))),
          ]))
        : ListView.builder(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: ps.playlists.length,
            itemBuilder: (_, i) {
              final p = ps.playlists[i];
              return GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(playlistId: p.id))),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border)),
                  child: Row(children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.queue_music,
                        color: _green, size: 24)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text(p.name, style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600,
                        color: Colors.white),
                        overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text('${p.videos.length} video${p.videos.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12, color: _label)),
                    ])),
                    const Icon(Icons.chevron_right,
                      color: _label, size: 20),
                  ]),
                ),
              );
            },
          ),
    );
  }

  void _showCreateDialog(BuildContext context, PlaylistService ps) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3C),
              borderRadius: BorderRadius.circular(2))),
          const Text('New Playlist', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(10)),
            child: TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(fontSize: 15, color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Playlist name',
                hintStyle: TextStyle(color: Color(0xFF8E8E93)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12)))),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              await ps.createPlaylist(name);
              if (context.mounted) _syncPlaylistsToBoard(context);
              if (context.mounted) Navigator.pop(context);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(12)),
              child: const Text('Create',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black,
                  fontWeight: FontWeight.w700)))),
        ]),
      ),
    );
  }

  void _confirmDelete(BuildContext context, PlaylistService ps,
      String id, String name) {
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
          Text('Delete "$name"?', style: const TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('This will permanently delete the playlist.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
                ps.deletePlaylist(id);
                _syncPlaylistsToBoard(context);
                Navigator.pop(context);
              },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _red, borderRadius: BorderRadius.circular(12)),
              child: const Text('Delete',
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


class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});
  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final _urlCtrl   = TextEditingController();
  final _titleCtrl = TextEditingController();
  bool _addingVideo  = false;
  bool _fetchingTitle = false;

  static const _bg    = Color(0xFF000000);
  static const _card  = Color(0xFF1C1C1E);
  static const _card2 = Color(0xFF2C2C2E);
  static const _border = Color(0xFF3A3A3C);
  static const _green = Color(0xFF30D158);
  static const _label = Color(0xFF8E8E93);
  static const _red   = Color(0xFFFF453A);
  static const _amber = Color(0xFFFF9F0A);

  @override
  void dispose() {
    _urlCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

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
      final client = HttpClient();
      final uri    = Uri.parse(
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json');
      final req  = await client.getUrl(uri).timeout(const Duration(seconds: 5));
      final res  = await req.close().timeout(const Duration(seconds: 5));
      final body = await res.transform(utf8.decoder).join();
      client.close();
      return (jsonDecode(body) as Map<String, dynamic>)['title']
          as String? ?? videoId;
    } catch (_) { return videoId; }
  }

  void _syncQueueIfPlaying(BuildContext context, PlaylistService ps) {
    final ble = context.read<BleService>();
    if (ble.state != ConnState.connected) return;
    final playlist = ps.playlists.firstWhere(
      (p) => p.id == widget.playlistId,
      orElse: () => Playlist(id: '', name: '', videos: []));
    if (playlist.id.isEmpty || playlist.videos.isEmpty) return;
    ble.sendQueue(playlist.videos);
  }

  Future<void> _addVideo(PlaylistService ps) async {
    final url    = _urlCtrl.text.trim();
    final manual = _titleCtrl.text.trim();
    if (url.isEmpty) return;
    final id = _extractId(url);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not a valid YouTube URL')));
      return;
    }
    String title = manual;
    if (title.isEmpty) {
      setState(() => _fetchingTitle = true);
      title = await _fetchTitle(id);
      if (mounted) setState(() => _fetchingTitle = false);
    }
    await ps.addVideo(widget.playlistId,
      QueueItem(videoId: id, title: title, url: url));
    _syncPlaylistsToBoard(context);
    _syncQueueIfPlaying(context, ps);
    _urlCtrl.clear(); _titleCtrl.clear();
    if (mounted) setState(() {});
  }

  void _confirmDeletePlaylist(BuildContext context, PlaylistService ps,
      String id, String name) {
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
          Text('Delete "$name"?', style: const TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('This will permanently delete the playlist.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              ps.deletePlaylist(id);
              _syncPlaylistsToBoard(context);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _red, borderRadius: BorderRadius.circular(12)),
              child: const Text('Delete',
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

  void _addFromWatchLater(PlaylistService ps) {
    final wl = context.read<WatchLaterService>();
    if (wl.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Watch Later items saved')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _WLPickerScreen(
        items: wl.items.toList(),
        onPickMultiple: (items) async {
          for (final item in items) {
            await ps.addVideo(widget.playlistId,
              QueueItem(
                videoId: item.videoId,
                title:   item.title.isNotEmpty ? item.title : item.videoId,
                url:     item.url));
          }
          _syncPlaylistsToBoard(context);
          _syncQueueIfPlaying(context, ps);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PlaylistService>();
    final ble = context.watch<BleService>();
    final playlist = ps.playlists.firstWhere(
      (p) => p.id == widget.playlistId,
      orElse: () => Playlist(id: '', name: '', videos: []));
    final connected = ble.state == ConnState.connected;
    final shuffle   = playlist.shuffle;
    final loop      = playlist.loop;
    final repeat    = playlist.repeat;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 17, color: _green),
          onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(playlist.name, style: const TextStyle(
            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          Text('${playlist.videos.length} video${playlist.videos.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 10, color: _label)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: _red, size: 22),
            onPressed: () => _confirmDeletePlaylist(context, ps, playlist.id, playlist.name)),
        ],
      ),
      body: Column(children: [
        // Play All + mode toggles
        if (playlist.videos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(children: [
              Row(children: [
                _modeChip(
                  icon: Icons.shuffle_rounded,
                  label: 'Shuffle',
                  active: shuffle,
                  color: const Color(0xFF0A84FF),
                  onTap: () {
                    final newShuffle = !shuffle;
                    context.read<PlaylistService>().updateModes(
                      playlist.id,
                      shuffle: newShuffle,
                      loop:    loop,
                      repeat:  newShuffle ? false : repeat,
                    );
                  },
                ),
                const SizedBox(width: 8),
                _modeChip(
                  icon: Icons.repeat_one_rounded,
                  label: 'Repeat',
                  active: repeat,
                  color: const Color(0xFFFF9F0A),
                  onTap: () {
                    final newRepeat = !repeat;
                    context.read<PlaylistService>().updateModes(
                      playlist.id,
                      shuffle: newRepeat ? false : shuffle,
                      loop:    newRepeat ? false : loop,
                      repeat:  newRepeat,
                    );
                  },
                ),
                const SizedBox(width: 8),
                _modeChip(
                  icon: Icons.repeat_rounded,
                  label: 'Loop',
                  active: loop,
                  color: const Color(0xFF30D158),
                  onTap: () {
                    final newLoop = !loop;
                    context.read<PlaylistService>().updateModes(
                      playlist.id,
                      shuffle: shuffle,
                      loop:    newLoop,
                      repeat:  newLoop ? false : repeat,
                    );
                  },
                ),
              ]),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: connected ? () {
                  final ble    = context.read<BleService>();
                  final videos = List<QueueItem>.from(playlist.videos);
                  if (shuffle) videos.shuffle();
                  ble.sendQueue(videos);
                  Future.delayed(const Duration(milliseconds: 300), () {
                    ble.queuePlay();
                  });
                  Future.delayed(const Duration(milliseconds: 600), () {
                    if (loop) {
                      ble.queueRepeatOff();
                      ble.queueLoopOn();
                    } else if (repeat) {
                      ble.queueLoopOff();
                      ble.queueRepeatOn();
                    } else {
                      ble.queueLoopOff();
                      ble.queueRepeatOff();
                    }
                  });
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: const Color(0xFF1C1C1E),
                    content: Text(
                      'Playing \${videos.length} videos\${shuffle ? " (shuffled)" : ""}\${loop ? " Loop" : ""}\${repeat ? " Repeat" : ""}',
                      style: const TextStyle(color: Colors.white))));
                } : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: connected
                      ? _green.withOpacity(0.15)
                      : const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: connected
                        ? _green.withOpacity(0.4)
                        : const Color(0xFF3A3A3C))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    Icon(Icons.play_arrow_rounded,
                      color: connected ? _green : _label, size: 22),
                    const SizedBox(width: 8),
                    Text('Play All', style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: connected ? _green : _label)),
                  ]),
                ),
              ),
            ]),
          ),

        // Video list
        Expanded(
          child: ReorderableListView.builder(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: playlist.videos.length,
            onReorder: (o, n) {
              ps.reorderVideo(widget.playlistId, o, n);
              _syncPlaylistsToBoard(context);
            },
            itemBuilder: (_, i) {
              final v = playlist.videos[i];
              return Container(
                key: ValueKey(v.url + i.toString()),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border)),
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: Icon(Icons.drag_handle, color: _label, size: 20))),
                  Text('${i+1}', style: const TextStyle(
                    fontSize: 12, color: _label)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(v.title.isNotEmpty ? v.title : v.videoId,
                    style: const TextStyle(fontSize: 13,
                      color: Colors.white, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis)),
                  GestureDetector(
                    onTap: () {
                      ps.removeVideo(widget.playlistId, i);
                      _syncPlaylistsToBoard(context);
                      _syncQueueIfPlaying(context, ps);
                    },
                    child: const Icon(Icons.close_rounded,
                      color: _label, size: 18)),
                ]),
              );
            },
          ),
        ),

        // Add video form / button
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0D),
            border: Border(top: BorderSide(color: _border))),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: _addingVideo
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                _field(_urlCtrl, 'YouTube URL'),
                const SizedBox(height: 8),
                _field(_titleCtrl, 'Title (leave blank to auto-fetch)'),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () => setState(() {
                      _addingVideo = false;
                      _urlCtrl.clear(); _titleCtrl.clear(); }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _card2,
                        borderRadius: BorderRadius.circular(10)),
                      child: const Text('Cancel',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: _label))))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: GestureDetector(
                    onTap: _fetchingTitle ? null : () => _addVideo(ps),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _green,
                        borderRadius: BorderRadius.circular(10)),
                      child: _fetchingTitle
                        ? const Center(child: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black)))
                        : const Text('Add',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14,
                              color: Colors.black,
                              fontWeight: FontWeight.w600))))),
                ]),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _addFromWatchLater(ps),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _amber.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _amber.withOpacity(0.3))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                      Icon(Icons.bookmark_outline_rounded,
                        size: 16, color: _amber),
                      SizedBox(width: 8),
                      Text('Add from Watch Later',
                        style: TextStyle(fontSize: 13,
                          color: _amber, fontWeight: FontWeight.w600)),
                    ]))),
              ])
            : Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => setState(() => _addingVideo = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _border)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                      Icon(Icons.add, color: _green, size: 18),
                      SizedBox(width: 6),
                      Text('Add Video', style: TextStyle(
                        fontSize: 14, color: _green,
                        fontWeight: FontWeight.w500)),
                    ])))),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _addFromWatchLater(ps),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _amber.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _amber.withOpacity(0.3))),
                    child: const Icon(Icons.bookmark_outline_rounded,
                      color: _amber, size: 20))),
              ]),
        ),
      ]),
    );
  }

  Widget _modeChip({
    required IconData icon,
    required String label,
    required bool active,
    required Color color,
    required VoidCallback onTap,
  }) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? color.withOpacity(0.5) : const Color(0xFF3A3A3C))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: active ? color : _label),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700,
            color: active ? color : _label, letterSpacing: 0.5)),
        ]),
      ),
    ),
  );

  Widget _field(TextEditingController ctrl, String hint) =>
    Container(
      decoration: BoxDecoration(
        color: _card2, borderRadius: BorderRadius.circular(10)),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(fontSize: 14, color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 14, color: _label),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10))));
}


class _WLPickerScreen extends StatefulWidget {
  final List<WatchLaterItem> items;
  final Function(List<WatchLaterItem>) onPickMultiple;
  const _WLPickerScreen({required this.items, required this.onPickMultiple});
  @override
  State<_WLPickerScreen> createState() => _WLPickerScreenState();
}

class _WLPickerScreenState extends State<_WLPickerScreen> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
            size: 17, color: Color(0xFF30D158)),
          onPressed: () => Navigator.pop(context)),
        title: Text(_selected.isEmpty
          ? 'Add from Watch Later'
          : '${_selected.length} selected',
          style: const TextStyle(color: Colors.white, fontSize: 17,
            fontWeight: FontWeight.w700)),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () {
                final picked = widget.items
                  .where((i) => _selected.contains(i.url)).toList();
                Navigator.pop(context);
                widget.onPickMultiple(picked);
              },
              child: const Text('Add', style: TextStyle(
                fontSize: 17, color: Color(0xFF30D158),
                fontWeight: FontWeight.w600))),
        ],
      ),
      body: ListView.builder(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: widget.items.length,
        itemBuilder: (_, i) {
          final item     = widget.items[i];
          final selected = _selected.contains(item.url);
          return GestureDetector(
            onTap: () => setState(() {
              if (selected) _selected.remove(item.url);
              else _selected.add(item.url);
            }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected
                  ? const Color(0xFF30D158).withOpacity(0.10)
                  : const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                    ? const Color(0xFF30D158).withOpacity(0.5)
                    : const Color(0xFF3A3A3C))),
              child: Row(children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                      ? const Color(0xFF30D158) : Colors.transparent,
                    border: Border.all(
                      color: selected
                        ? const Color(0xFF30D158)
                        : const Color(0xFF4A5568), width: 2)),
                  child: selected
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.black)
                    : null),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(item.title.isNotEmpty ? item.title : item.videoId,
                    style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w600, color: Colors.white),
                    overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(item.addedAt, style: const TextStyle(
                    fontSize: 11, color: Color(0xFF8E8E93))),
                ])),
              ]),
            ),
          );
        },
      ),
    );
  }
}
