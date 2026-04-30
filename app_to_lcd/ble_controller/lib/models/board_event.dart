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

class BoardEvent {
  final String event;
  final Map<String, dynamic> data;
  BoardEvent({required this.event, required this.data});

  factory BoardEvent.fromBytes(List<int> bytes) {
    try {
      final str  = utf8.decode(bytes, allowMalformed: true);
      final json = jsonDecode(str) as Map<String, dynamic>;
      return BoardEvent(event: json['event'] ?? '', data: json);
    } catch (e) {
      // ignore truncated/malformed BLE packets
      return BoardEvent(event: 'unknown', data: {});
    }
  }
}
