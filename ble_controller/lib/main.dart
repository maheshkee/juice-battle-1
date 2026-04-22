import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'services/board_state.dart';
import 'screens/hub_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const BLEHubApp());
}

class BLEHubApp extends StatelessWidget {
  const BLEHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<BleService>(
          create: (_) => BleService(),
          dispose: (_, svc) => svc.dispose(),
        ),
        ChangeNotifierProvider<BoardState>(create: (_) => BoardState()),
      ],
      child: MaterialApp(
        title: 'BLE Hub',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF080C14),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00E5FF),
            secondary: Color(0xFFFF6B35),
            surface: Color(0xFF111827),
            error: Color(0xFFFF3D71),
          ),
          useMaterial3: true,
        ),
        home: const HubScreen(),
      ),
    );
  }
}
