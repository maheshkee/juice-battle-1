import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/board_event.dart';

class WatchLaterService extends ChangeNotifier {
  List<WatchLaterItem> _items   = [];
  List<WatchLaterItem> _pending = [];

  List<WatchLaterItem> get items   => List.unmodifiable(_items);
  List<WatchLaterItem> get pending => List.unmodifiable(_pending);
  int get pendingCount => _pending.length;

  Future<void> load() async {
    print('[WL] Loading watch later...');
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('watch_later') ?? '[]';
    final praw  = prefs.getString('watch_later_pending') ?? '[]';
    try {
      _items   = (jsonDecode(raw)  as List).map((e) => WatchLaterItem.fromJson(e)).toList();
      _pending = (jsonDecode(praw) as List).map((e) => WatchLaterItem.fromJson(e)).toList();
    } catch (_) {}
    print('[WL] Loaded \${_items.length} items, \${_pending.length} pending');
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('watch_later',
        jsonEncode(_items.map((e) => e.toJson()).toList()));
    await prefs.setString('watch_later_pending',
        jsonEncode(_pending.map((e) => e.toJson()).toList()));
  }

  // called from share sheet or manually
  Future<void> addItem(WatchLaterItem item, {bool boardConnected = false}) async {
    // avoid duplicates
    _items.removeWhere((e) => e.url == item.url);
    _items.insert(0, item);
    if (!boardConnected) {
      _pending.removeWhere((e) => e.url == item.url);
      _pending.add(item);
    }
    await _save();
    notifyListeners();
  }

  Future<void> removeItem(String url) async {
    _items.removeWhere((e) => e.url == url);
    _pending.removeWhere((e) => e.url == url);
    await _save();
    notifyListeners();
  }

  // called when board connects — returns pending items to flush
  List<WatchLaterItem> flushPending() {
    final items = List<WatchLaterItem>.from(_pending);
    _pending.clear();
    _save();
    notifyListeners();
    return items;
  }

  // called when board pushes updated list
  void syncFromBoard(List<WatchLaterItem> boardItems) {
    // merge — board is source of truth, but keep pending
    _items = boardItems;
    // re-add pending items not yet on board
    for (final p in _pending) {
      if (!_items.any((e) => e.url == p.url)) {
        _items.insert(0, p);
      }
    }
    _save();
    notifyListeners();
  }
}
