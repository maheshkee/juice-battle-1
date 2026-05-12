import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/board_event.dart';

class WatchLaterService extends ChangeNotifier {
  List<WatchLaterItem> _items           = [];
  List<WatchLaterItem> _pending         = [];
  List<String>         _pendingRemovals = [];

  List<WatchLaterItem> get items           => List.unmodifiable(_items);
  List<WatchLaterItem> get pending         => List.unmodifiable(_pending);
  int                  get pendingCount    => _pending.length;
  List<String>         get pendingRemovals => List.unmodifiable(_pendingRemovals);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('watch_later')          ?? '[]';
    final praw  = prefs.getString('watch_later_pending')  ?? '[]';
    final rraw  = prefs.getString('watch_later_removals') ?? '[]';
    try {
      _items           = (jsonDecode(raw)  as List).map((e) => WatchLaterItem.fromJson(e)).toList();
      _pending         = (jsonDecode(praw) as List).map((e) => WatchLaterItem.fromJson(e)).toList();
      _pendingRemovals = (jsonDecode(rraw) as List).cast<String>();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('watch_later',
        jsonEncode(_items.map((e) => e.toJson()).toList()));
    await prefs.setString('watch_later_pending',
        jsonEncode(_pending.map((e) => e.toJson()).toList()));
    await prefs.setString('watch_later_removals',
        jsonEncode(_pendingRemovals));
  }

  Future<void> addItem(WatchLaterItem item, {bool boardConnected = false}) async {
    _items.removeWhere((e) => e.url == item.url);
    _items.insert(0, item);
    _pendingRemovals.remove(item.url);
    if (!boardConnected) {
      _pending.removeWhere((e) => e.url == item.url);
      _pending.add(item);
    }
    await _save();
    notifyListeners();
  }

  Future<void> removeItem(String url, {bool boardConnected = false}) async {
    _items.removeWhere((e) => e.url == url);
    _pending.removeWhere((e) => e.url == url);
    if (!boardConnected) {
      if (!_pendingRemovals.contains(url)) {
        _pendingRemovals.add(url);
      }
    }
    await _save();
    notifyListeners();
  }

  List<WatchLaterItem> flushPending() {
    final items = List<WatchLaterItem>.from(_pending);
    _pending.clear();
    _save();
    notifyListeners();
    return items;
  }

  List<String> flushPendingRemovals() {
    // don't clear yet — keep until board confirms via syncFromBoard
    return List<String>.from(_pendingRemovals);
  }

  // phone is source of truth — only add new items from board,
  // skip anything in pending removals
  void syncFromBoard(List<WatchLaterItem> boardItems) {
    bool changed = false;
    for (final b in boardItems) {
      if (_pendingRemovals.contains(b.url)) continue;
      if (!_items.any((e) => e.url == b.url)) {
        _items.add(b);
        changed = true;
      }
    }
    if (changed) {
      _save();
      notifyListeners();
    }
  }
}
