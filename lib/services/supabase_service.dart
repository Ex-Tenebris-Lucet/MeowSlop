import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<bool> testConnection() async {
    try {
      // Test connection using a health check
      await _client.from('_supabase_health').select();
      print('Supabase connection successful!');
      return true;
    } on AuthException catch (e) {
      print('Supabase auth error: ${e.message}');
      return false;
    } on PostgrestException catch (e) {
      // This is actually expected as the health table doesn't exist
      // But if we get here, it means we connected successfully
      print('Supabase connected (expected error: ${e.message})');
      return true;
    } catch (e) {
      print('Supabase unexpected error: $e');
      return false;
    }
  }
} 