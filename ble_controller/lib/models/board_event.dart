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

class ScannedDevice {
  final String mac;
  final String name;
  final int rssi;
  ScannedDevice({required this.mac, required this.name, required this.rssi});
  factory ScannedDevice.fromJson(Map<String, dynamic> j) => ScannedDevice(
    mac: j['mac'] ?? '', name: j['name'] ?? '', rssi: j['rssi'] ?? -99);
}

class ConnectedDevice {
  final String mac;
  final String name;
  final List<CharacteristicInfo> characteristics;
  ConnectedDevice({required this.mac, required this.name, required this.characteristics});
  factory ConnectedDevice.fromJson(Map<String, dynamic> j) => ConnectedDevice(
    mac: j['mac'] ?? '', name: j['name'] ?? '',
    characteristics: (j['characteristics'] as List? ?? [])
        .map((c) => CharacteristicInfo.fromJson(c as Map<String, dynamic>)).toList());
}

class CharacteristicInfo {
  final String uuid;
  final String name;
  final String value;
  final List<String> flags;
  CharacteristicInfo({required this.uuid, required this.name, required this.value, required this.flags});
  factory CharacteristicInfo.fromJson(Map<String, dynamic> j) => CharacteristicInfo(
    uuid: j['uuid'] ?? '', name: j['name'] ?? '', value: j['value'] ?? '',
    flags: List<String>.from(j['flags'] ?? []));
}

class HistoryItem {
  final String url;
  final String videoId;
  final String time;
  HistoryItem({required this.url, required this.videoId, required this.time});
  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
    url: j['url'] ?? '', videoId: j['video_id'] ?? '', time: j['time'] ?? '');
}

class TrustedDevice {
  final String mac;
  final String name;
  TrustedDevice({required this.mac, required this.name});
  factory TrustedDevice.fromJson(Map<String, dynamic> j) => TrustedDevice(
    mac: j['mac'] ?? '', name: j['name'] ?? '');
}
