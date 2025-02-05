import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/device_service.dart';
import 'screens/splash_screen.dart';

// Our cat-themed colors
class MeowColors {
  static const voidBlack = Color(0xFF000000);
  static const voidGrey = Color(0xFF1A1A1A);
  static const voidAccent = Color(0xFFFFE66D); // Cat eye color!
  static const creamWhite = Color(0xFFFFF9F4);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  final deviceService = await DeviceService.create();
  final deviceId = await deviceService.getOrCreateDeviceId();
  print('Device ID: $deviceId'); // For testing, we'll remove this later
  
  runApp(MeowSlopApp(deviceService: deviceService));
}

class MeowSlopApp extends StatelessWidget {
  final DeviceService deviceService;
  
  const MeowSlopApp({super.key, required this.deviceService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeowSlop',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: MeowColors.voidBlack,
        colorScheme: const ColorScheme.dark(
          primary: MeowColors.voidAccent,
          secondary: MeowColors.voidGrey,
          surface: MeowColors.voidGrey,
          onPrimary: MeowColors.voidBlack,
          onSecondary: MeowColors.creamWhite,
          onSurface: MeowColors.creamWhite,
        ),
      ),
      home: SplashScreen(deviceService: deviceService),
    );
  }
}
