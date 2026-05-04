import 'dart:convert';

class QueueItem {
  final String videoId;
  final String title;
  final String url;

  QueueItem({required this.videoId, required this.title, required this.url});
  Map<String, dynamic> toJson() => {'video_id': videoId, 'title': title, 'url': url};
  factory QueueItem.fromJson(Map<String, dynamic> j) => QueueItem(
    videoId: j['video_id'] ?? '', title: j['title'] ?? '', url: j['url'] ?? '');
}

class HistoryItem {
  final String url;
  final String time;
  final String title;
  HistoryItem({required this.url, required this.time, this.title = ''});
  factory HistoryItem.fromJson(Map<String, dynamic> j) =>
      HistoryItem(url: j['url'] ?? '', time: j['time'] ?? '', title: j['title'] ?? '');
}

class QueueStatus {
  final bool   active;
  final bool   paused;
  final int    index;
  final int    total;
  final List<QueueItem> queue;
  final QueueItem?      current;

  QueueStatus({required this.active, required this.paused,
    required this.index, required this.total, required this.queue, this.current});

  factory QueueStatus.empty() => QueueStatus(
    active: false, paused: false, index: -1, total: 0, queue: [], current: null);

  factory QueueStatus.fromJson(Map<String, dynamic> j) => QueueStatus(
    active:  j['active']  ?? false,
    paused:  j['paused']  ?? false,
    index:   j['index']   ?? -1,
    total:   j['total']   ?? 0,
    queue:   (j['queue'] as List? ?? []).map((e) => QueueItem.fromJson(e)).toList(),
    current: j['current'] != null ? QueueItem.fromJson(j['current']) : null,
  );
}

class ScheduleEntry {
  final DateTime date;
  final List<QueueItem> playlist;

  ScheduleEntry({required this.date, required this.playlist});

  Map<String, dynamic> toJson() => {
    'date': '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}',
    'playlist': playlist.map((p) => p.toJson()).toList(),
  };

  factory ScheduleEntry.fromJson(Map<String, dynamic> j) => ScheduleEntry(
    date:     DateTime.parse(j['date']),
    playlist: (j['playlist'] as List? ?? []).map((e) => QueueItem.fromJson(e)).toList(),
  );
}

class WatchLaterItem {
  final String url;
  final String title;
  final String videoId;
  final String addedAt;

  WatchLaterItem({
    required this.url,
    required this.title,
    required this.videoId,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'url':      url,
    'title':    title,
    'video_id': videoId,
    'added_at': addedAt,
  };

  factory WatchLaterItem.fromJson(Map<String, dynamic> j) => WatchLaterItem(
    url:      j['url']      ?? '',
    title:    j['title']    ?? '',
    videoId:  j['video_id'] ?? '',
    addedAt:  j['added_at'] ?? '',
  );
}

// reassembly buffer — keyed by first chunk index to handle concurrent events
final Map<int, _ChunkBuffer> _buffers = {};

class _ChunkBuffer {
  final int total;
  final Map<int, List<int>> chunks = {};
  final DateTime created = DateTime.now();

  _ChunkBuffer(this.total);

  bool get isComplete => chunks.length == total;

  List<int> assemble() {
    final result = <int>[];
    for (int i = 0; i < total; i++) {
      result.addAll(chunks[i] ?? []);
    }
    return result;
  }
}

class BoardEvent {
  final String event;
  final Map<String, dynamic> data;
  BoardEvent({required this.event, required this.data});

  static BoardEvent? tryFromBytes(List<int> bytes) {
    if (bytes.length < 3) return null;
    try {
      final idx   = bytes[0];
      final total = bytes[1];
      final chunk = bytes.sublist(2);

      if (total == 1) {
        // single chunk — parse directly
        final str  = utf8.decode(chunk, allowMalformed: true);
        final json = jsonDecode(str) as Map<String, dynamic>;
        return BoardEvent(event: json['event'] ?? '', data: json);
      }

      // multi-chunk — buffer
      _buffers[idx == 0 ? DateTime.now().millisecondsSinceEpoch : idx] ??=
          _ChunkBuffer(total);

      // find the right buffer for this total
      _ChunkBuffer? buf;
      for (final b in _buffers.values) {
        if (b.total == total && !b.chunks.containsKey(idx)) {
          buf = b;
          break;
        }
      }
      buf ??= _ChunkBuffer(total);
      buf.chunks[idx] = chunk;

      if (buf.isComplete) {
        final assembled = buf.assemble();
        // clean up old buffers
        _buffers.removeWhere((k, v) =>
          v == buf ||
          DateTime.now().difference(v.created).inSeconds > 10);
        final str  = utf8.decode(assembled, allowMalformed: true);
        final json = jsonDecode(str) as Map<String, dynamic>;
        return BoardEvent(event: json['event'] ?? '', data: json);
      }
      return null; // not complete yet
    } catch (_) {
      return null;
    }
  }

  factory BoardEvent.fromBytes(List<int> bytes) {
    return tryFromBytes(bytes) ?? BoardEvent(event: 'unknown', data: {});
  }
}
