import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  factory SupabaseService() => instance;
  SupabaseService._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  SupabaseClient? get client => _isInitialized ? Supabase.instance.client : null;

  Future<void> initialize({required String url, required String anonKey}) async {
    if (url.isEmpty || anonKey.isEmpty || url.contains('YOUR_PROJECT')) {
      debugPrint('Supabase credentials not provided. Running in Demo / Local Offline mode.');
      _isInitialized = false;
      return;
    }

    try {
      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
        debug: kDebugMode,
      );
      _isInitialized = true;
      debugPrint('Supabase initialized successfully.');
    } catch (e) {
      debugPrint('Supabase Initialization Error: $e');
      _isInitialized = false;
    }
  }
}
