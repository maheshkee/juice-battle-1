import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/board_event.dart';

class Playlist {
  final String id;
  String name;
  List<QueueItem> videos;

  Playlist({required this.id, required this.name, required this.videos});

  Map<String, dynamic> toJson() => {
    'id':     id,
    'name':   name,
    'videos': videos.map((v) => v.toJson()).toList(),
  };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
    id:     j['id']   ?? '',
    name:   j['name'] ?? '',
    videos: (j['videos'] as List? ?? [])
        .map((v) => QueueItem.fromJson(v)).toList(),
  );
}

class PlaylistService extends ChangeNotifier {
  List<Playlist> _playlists = [];
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('playlists') ?? '[]';
      _playlists  = (jsonDecode(raw) as List)
          .map((e) => Playlist.fromJson(e)).toList();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playlists',
          jsonEncode(_playlists.map((p) => p.toJson()).toList()));
    } catch (_) {}
  }

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

  Future<void> reorderVideo(String id, int oldIndex, int newIndex) async {
    final p = _playlists.firstWhere((p) => p.id == id);
    if (newIndex > oldIndex) newIndex--;
    final item = p.videos.removeAt(oldIndex);
    p.videos.insert(newIndex, item);
    await _save();
    notifyListeners();
  }
}
