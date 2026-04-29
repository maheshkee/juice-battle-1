import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'services/board_state.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const YTDisplayApp());
}

class YTDisplayApp extends StatelessWidget {
  const YTDisplayApp({super.key});

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
        title: 'YT Display',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF080C14),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF0000),
            secondary: Color(0xFF00E5FF),
            surface: Color(0xFF111827),
            error: Color(0xFFFF3D71),
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
