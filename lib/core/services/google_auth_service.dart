import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  static final GoogleAuthService instance = GoogleAuthService._internal();
  factory GoogleAuthService() => instance;
  GoogleAuthService._internal();

  // Supplied at build time via --dart-define; see the README's Google OAuth
  // section. clientId is the platform (Android/iOS) OAuth client ID and
  // serverClientId is the Web OAuth client ID the idToken is minted for.
  static const _clientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;

  bool _initialized = false;

  /// google_sign_in 7.x requires initialize() exactly once before any other
  /// call; running authenticate() uninitialized fails on Android.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: _clientId.isEmpty ? null : _clientId,
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
    _initialized = true;
  }

  /// Returns null only when the user dismissed the account picker; any real
  /// failure is thrown so the caller can surface it.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      await _ensureInitialized();
      _currentUser = await GoogleSignIn.instance.authenticate();
      return _currentUser;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _currentUser = null;
  }
}
