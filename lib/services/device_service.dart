import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

class DeviceService {
  static const String _deviceIdKey = 'device_id';
  final SharedPreferences _prefs;
  
  DeviceService._(this._prefs);
  
  static Future<DeviceService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return DeviceService._(prefs);
  }

  Future<String> getOrCreateDeviceId() async {
    String? deviceId = _prefs.getString(_deviceIdKey);
    
    if (deviceId == null) {
      // Generate a new device ID using device info and UUID
      final deviceInfo = DeviceInfoPlugin();
      const uuid = Uuid();
      
      final androidInfo = await deviceInfo.androidInfo;
      // Combine device info with UUID for uniqueness
      deviceId = '${androidInfo.id}_${uuid.v4()}';
          
      await _prefs.setString(_deviceIdKey, deviceId);
    }
    
    return deviceId;
  }

  // Save user preferences
  Future<void> savePreference(String key, dynamic value) async {
    if (value is String) {
      await _prefs.setString(key, value);
    } else if (value is bool) {
      await _prefs.setBool(key, value);
    } else if (value is int) {
      await _prefs.setInt(key, value);
    } else if (value is double) {
      await _prefs.setDouble(key, value);
    } else if (value is List<String>) {
      await _prefs.setStringList(key, value);
    }
  }

  // Get a preference
  T? getPreference<T>(String key) {
    return _prefs.get(key) as T?;
  }
} 