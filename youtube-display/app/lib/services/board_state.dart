import 'package:flutter/foundation.dart';
import '../models/queue_item.dart';

class QueueState {
  final String status;        // idle / playing / paused
  final int    currentIndex;
  final int    total;
  final String videoId;
  final String title;

  const QueueState({
    this.status       = 'idle',
    this.currentIndex = 0,
    this.total        = 0,
    this.videoId      = '',
    this.title        = '',
  });

  QueueState copyWith({
    String? status, int? currentIndex, int? total,
    String? videoId, String? title,
  }) => QueueState(
    status:       status       ?? this.status,
    currentIndex: currentIndex ?? this.currentIndex,
    total:        total        ?? this.total,
    videoId:      videoId      ?? this.videoId,
    title:        title        ?? this.title,
  );
}

class LocalFileInfo {
  final String filename;
  final String title;
  final double sizeMb;
  LocalFileInfo({required this.filename, required this.title, required this.sizeMb});
  factory LocalFileInfo.fromJson(Map<String, dynamic> j) => LocalFileInfo(
    filename: j['filename'] ?? '',
    title:    j['title']    ?? '',
    sizeMb:   (j['size_mb'] ?? 0).toDouble(),
  );
}

class BoardState extends ChangeNotifier {
  // ── YouTube single play ───────────────────────────────────────────────────
  String?      currentUrl;
  List<String> urlHistory = [];

  // ── Queue ─────────────────────────────────────────────────────────────────
  List<QueueItem> pendingQueue = [];   // queue being built on phone
  QueueState      queueState   = const QueueState();

  // ── Local files ───────────────────────────────────────────────────────────
  List<LocalFileInfo> localFiles       = [];
  String              localStatus      = 'idle';
  String              localFilename    = '';
  bool                usbImporting     = false;
  int                 usbProgress      = 0;

  // ── Logs ──────────────────────────────────────────────────────────────────
  List<String> logs = [];

  // ── Log ───────────────────────────────────────────────────────────────────
  void addLog(String msg) {
    logs.insert(0, msg);
    if (logs.length > 100) logs.removeLast();
    notifyListeners();
  }

  // ── YouTube single play ───────────────────────────────────────────────────
  void setCurrentUrl(String url) {
    currentUrl = url;
    if (!urlHistory.contains(url)) {
      urlHistory.insert(0, url);
      if (urlHistory.length > 10) urlHistory.removeLast();
    }
    notifyListeners();
  }

  void clearCurrentUrl() {
    currentUrl = null;
    notifyListeners();
  }

  // ── Queue builder ─────────────────────────────────────────────────────────
  void addToQueue(QueueItem item) {
    pendingQueue.add(item);
    notifyListeners();
  }

  void removeFromQueue(int index) {
    pendingQueue.removeAt(index);
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = pendingQueue.removeAt(oldIndex);
    pendingQueue.insert(newIndex, item);
    notifyListeners();
  }

  void clearPendingQueue() {
    pendingQueue.clear();
    notifyListeners();
  }

  // ── Queue state from board ────────────────────────────────────────────────
  void updateQueueState(Map<String, dynamic> json) {
    queueState = QueueState(
      status:       json['status']        ?? 'idle',
      currentIndex: json['current_index'] ?? 0,
      total:        json['total']         ?? 0,
      videoId:      json['videoId']       ?? '',
      title:        json['title']         ?? '',
    );
    notifyListeners();
  }

  // ── Local files ───────────────────────────────────────────────────────────
  void updateLocalFiles(List<dynamic> files) {
    localFiles = files
        .map((f) => LocalFileInfo.fromJson(f as Map<String, dynamic>))
        .toList();
    notifyListeners();
  }

  void updateLocalStatus(Map<String, dynamic> json) {
    localStatus   = json['status']   ?? 'idle';
    localFilename = json['filename'] ?? '';
    notifyListeners();
  }

  void updateUsbImport(Map<String, dynamic> json) {
    final status = json['status'] as String? ?? '';
    if (status == 'importing') {
      usbImporting = true;
      usbProgress  = json['progress'] as int? ?? 0;
    } else {
      usbImporting = false;
      usbProgress  = 0;
    }
    notifyListeners();
  }

  void usbImportDone(Map<String, dynamic> json) {
    usbImporting = false;
    usbProgress  = 0;
    final files = json['files'] as List? ?? [];
    updateLocalFiles(files);
    notifyListeners();
  }
}
