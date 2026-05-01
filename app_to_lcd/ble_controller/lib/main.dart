import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'services/board_state.dart';
import 'screens/hub_screen.dart';

const _platform = MethodChannel('com.gratian.ble_controller/share');

void startKeepAlive() => _platform.invokeMethod('startKeepAlive').catchError((_) {});
void stopKeepAlive()  => _platform.invokeMethod('stopKeepAlive').catchError((_) {});

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BoardState()),
        Provider(create: (_) => BleService()),
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
        if (url != null && url.isNotEmpty) {
          final ble = context.read<BleService>();
          if (ble.state == ConnState.connected) ble.sendUrl(url);
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
      ),
      home: const HubScreen(),
    );
  }
}
