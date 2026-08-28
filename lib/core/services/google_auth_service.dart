import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  static final GoogleAuthService instance = GoogleAuthService._internal();
  factory GoogleAuthService() => instance;
  GoogleAuthService._internal();

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;

  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await GoogleSignIn.instance.authenticate();
      return _currentUser;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _currentUser = null;
  }
}
