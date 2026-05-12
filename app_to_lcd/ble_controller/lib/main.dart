import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'services/board_state.dart';
import 'services/watch_later_service.dart';
import 'services/bt_audio_service.dart';
import 'services/playlist_service.dart';
import 'screens/hub_screen.dart';
import 'models/board_event.dart';

const _platform = MethodChannel('com.gratian.ble_controller/share');

void startKeepAlive() => _platform.invokeMethod('startKeepAlive').catchError((_) {});
void stopKeepAlive()  => _platform.invokeMethod('stopKeepAlive').catchError((_) {});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final wlService  = WatchLaterService();
  final plService  = PlaylistService();
  await wlService.load();
  await plService.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BoardState()),
        Provider(create: (_) => BleService()),
        ChangeNotifierProvider(create: (_) => BtAudioService()),
        ChangeNotifierProvider.value(value: wlService),
        ChangeNotifierProvider.value(value: plService),
      ],
      child: const BleHubApp(),
    ),
  );
}

class BleHubApp extends StatefulWidget {
  const BleHubApp({super.key});
  @override
  State<BleHubApp> createState() => _BleHubAppState();
}

class _BleHubAppState extends State<BleHubApp> {
  @override
  void initState() {
    super.initState();
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'sharedUrl') {
        final url = call.arguments as String?;
        if (url == null || url.isEmpty) return;
        final ble = context.read<BleService>();
        final wl  = context.read<WatchLaterService>();
        String videoId = '';
        for (final p in [
          RegExp(r'(?:v=)([A-Za-z0-9_-]{11})'),
          RegExp(r'(?:youtu\.be/)([A-Za-z0-9_-]{11})'),
          RegExp(r'(?:shorts/)([A-Za-z0-9_-]{11})'),
        ]) {
          final m = p.firstMatch(url);
          if (m != null) { videoId = m.group(1)!; break; }
        }
        String title = '';
        try {
          final client = HttpClient();
          final uri    = Uri.parse(
            'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json');
          final req    = await client.getUrl(uri)
              .timeout(const Duration(seconds: 5));
          final res    = await req.close()
              .timeout(const Duration(seconds: 5));
          final body   = await res.transform(utf8.decoder).join();
          client.close();
          title = (jsonDecode(body) as Map<String, dynamic>)['title']
              as String? ?? '';
        } catch (_) {}
        final item = WatchLaterItem(
          url:      url,
          title:    title,
          videoId:  videoId,
          addedAt:  DateTime.now().toString().substring(11, 16),
        );
        final connected = ble.state == ConnState.connected;
        await wl.addItem(item, boardConnected: connected);
        if (connected) {
          ble.watchLaterAdd(url, title, videoId);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0F1E),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF00E5FF)),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,

      ),
      home: const HubScreen(),
    );
  }
}
