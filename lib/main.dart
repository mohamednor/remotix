// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'core/network/ssdp_discovery.dart';
import 'core/utils/app_logger.dart';
import 'data/repositories/device_repository_impl.dart';
import 'domain/usecases/discover_devices_usecase.dart';
import 'presentation/providers/device_provider.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/device_scan_screen.dart';
import 'presentation/screens/device_list_screen.dart';
import 'presentation/screens/remote_control_screen.dart';
import 'presentation/screens/debug_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await MobileAds.instance.initialize();
  AppLogger.i('AdMob initialized');
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const RemotixApp());
}

class RemotixApp extends StatelessWidget {
  const RemotixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => DeviceProvider(
            DiscoverDevicesUseCase(
              DeviceRepositoryImpl(SsdpDiscovery()),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Remotix',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashScreen(),
          '/scan': (_) => const DeviceScanScreen(),
          '/devices': (_) => const DeviceListScreen(),
          '/remote': (_) => const RemoteControlScreen(),
          '/debug': (_) => const DebugScreen(),
        },
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF12121F),
      primaryColor: const Color(0xFF6C63FF),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF6C63FF),
        secondary: Color(0xFFFF6584),
        surface: Color(0xFF1E1E2E),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A2E),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Color(0xFFCCCCDD)),
        bodySmall: TextStyle(color: Color(0xFF9090B0)),
      ),
      useMaterial3: true,
    );
  }
}
