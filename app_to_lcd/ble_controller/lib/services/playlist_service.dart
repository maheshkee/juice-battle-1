import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/board_event.dart';

class Playlist {
  final String id;
  String name;
  List<QueueItem> videos;
  bool shuffle;
  bool loop;
  bool repeat;

  Playlist({
    required this.id,
    required this.name,
    required this.videos,
    this.shuffle = false,
    this.loop    = false,
    this.repeat  = false,
  });

  Map<String, dynamic> toJson() => {
    'id':      id,
    'name':    name,
    'videos':  videos.map((v) => v.toJson()).toList(),
    'shuffle': shuffle,
    'loop':    loop,
    'repeat':  repeat,
  };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
    id:      j['id']      ?? '',
    name:    j['name']    ?? '',
    shuffle: j['shuffle'] ?? false,
    loop:    j['loop']    ?? false,
    repeat:  j['repeat']  ?? false,
    videos:  (j['videos'] as List? ?? [])
        .map((v) => QueueItem.fromJson(Map<String, dynamic>.from(v))).toList(),
  );
}

class PlaylistService extends ChangeNotifier {
  List<Playlist> _playlists = [];
  bool _dirty = false;

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  bool get dirty => _dirty;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('playlists') ?? '[]';
      final list  = jsonDecode(raw) as List;
      _playlists  = list
          .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      print('[PLAYLIST] load error: $e');
    }
    notifyListeners();
  }

  Future<void> _save({bool dirty = true}) async {
    if (dirty) _dirty = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playlists',
          jsonEncode(_playlists.map((p) => p.toJson()).toList()));
    } catch (_) {}
  }

  void markClean() {
    _dirty = false;
    notifyListeners();
  }

  void syncFromBoard(List<dynamic> boardPlaylists) {
    try {
      _playlists = boardPlaylists
          .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _dirty = false;
      _save(dirty: false);
      notifyListeners();
    } catch (e) {
      print('[PLAYLIST] syncFromBoard error: $e');
    }
  }

  List<Map<String, dynamic>> toJsonList() =>
      _playlists.map((p) => p.toJson()).toList();

  Future<void> createPlaylist(String name) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _playlists.add(Playlist(id: id, name: name, videos: []));
    await _save();
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    _playlists.removeWhere((p) => p.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> renamePlaylist(String id, String name) async {
    final p = _playlists.firstWhere((p) => p.id == id);
    p.name = name;
    await _save();
    notifyListeners();
  }

  Future<void> addVideo(String id, QueueItem video) async {
    final p = _playlists.firstWhere((p) => p.id == id);
    p.videos.add(video);
    await _save();
    notifyListeners();
  }

  Future<void> removeVideo(String id, int index) async {
    final p = _playlists.firstWhere((p) => p.id == id);
    p.videos.removeAt(index);
    await _save();
    notifyListeners();
  }

  void updateModes(String id, {required bool shuffle, required bool loop, required bool repeat}) {
    final p = _playlists.firstWhere((p) => p.id == id, orElse: () => Playlist(id: '', name: '', videos: []));
    if (p.id.isEmpty) return;
    p.shuffle = shuffle;
    p.loop    = loop;
    p.repeat  = repeat;
    _save();
    notifyListeners();
  }

  Future<void> reorderVideo(String id, int oldIndex, int newIndex) async {
    final p = _playlists.firstWhere((p) => p.id == id);
    if (newIndex > oldIndex) newIndex--;
    final item = p.videos.removeAt(oldIndex);
    p.videos.insert(newIndex, item);
    await _save();
    notifyListeners();
  }
}
