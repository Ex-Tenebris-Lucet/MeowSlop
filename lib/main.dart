import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await dotenv.load(fileName: ".env");
    
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
    
    if (supabaseUrl == null || supabaseAnonKey == null) {
      throw Exception('Missing Supabase URL or anon key in .env file');
    }
    
    // Initialize Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    
    final deviceService = await DeviceService.create();
    final deviceId = await deviceService.getOrCreateDeviceId();
    print('Device ID: $deviceId'); // For testing, we'll remove this later
    
    runApp(MeowSlopApp(deviceService: deviceService));
  } catch (e) {
    print('Failed to initialize app: $e');
    // In a real app, you might want to show an error screen here
    runApp(const MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Failed to initialize app',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    ));
  }
}

class MeowSlopApp extends StatelessWidget {
  final DeviceService deviceService;
  
  const MeowSlopApp({super.key, required this.deviceService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeowSlop',
      builder: (context, widget) {
        ErrorWidget.builder = (FlutterErrorDetails details) {
          return Container(
            color: MeowColors.voidBlack,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: MeowColors.voidAccent,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Something went wrong',
                    style: TextStyle(
                      color: MeowColors.creamWhite,
                      fontSize: 18,
                    ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        details.exception.toString(),
                        style: TextStyle(
                          color: MeowColors.creamWhite.withOpacity(0.7),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        };
        return widget ?? const SizedBox.shrink();
      },
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
