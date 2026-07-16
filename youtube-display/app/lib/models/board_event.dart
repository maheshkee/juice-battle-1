import 'dart:convert';

class BoardEvent {
  final String event;
  final Map<String, dynamic> payload;

  BoardEvent({required this.event, required this.payload});

  factory BoardEvent.fromBytes(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final event = json['event'] as String? ?? 'unknown';
      final payload = Map<String, dynamic>.from(json)..remove('event');
      return BoardEvent(event: event, payload: payload);
    } catch (_) {
      return BoardEvent(event: 'unknown', payload: {});
    }
  }
}
