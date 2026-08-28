import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../core/services/google_drive_service.dart';
import '../core/services/supabase_service.dart';

final authProvider = StateNotifierProvider<AuthNotifier, UserProfile?>((ref) {
  final notifier = AuthNotifier();
  notifier.restoreSession();
  return notifier;
});

class AuthNotifier extends StateNotifier<UserProfile?> {
  AuthNotifier()
      : super(SupabaseService.instance.isInitialized ? null : UserProfile.demo());

  /// Restores a persisted Supabase session after an app restart.
  Future<void> restoreSession() async {
    final client = SupabaseService.instance.client;
    if (client == null) return;
    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) return;

    final metadata = sessionUser.userMetadata ?? const {};
    state = UserProfile(
      id: sessionUser.id,
      email: sessionUser.email ?? '',
      displayName: (metadata['full_name'] as String?) ??
          (metadata['name'] as String?) ??
          sessionUser.email ??
          'User',
      avatarUrl: metadata['avatar_url'] as String?,
    );
  }

  Future<void> signInWithGoogle() async {
    final googleUser = await GoogleDriveService.instance.signIn();
    if (googleUser == null) return;

    final supabaseClient = SupabaseService.instance.client;
    if (supabaseClient != null) {
      try {
        final googleAuth = googleUser.authentication;
        final idToken = googleAuth.idToken;
        if (idToken == null) {
          // google_sign_in does not expose an idToken on web; keep the
          // offline profile below as a fallback.
          debugPrint('Google idToken unavailable, using offline profile.');
        } else {
          await supabaseClient.auth.signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
          );

          final user = supabaseClient.auth.currentUser;
          if (user != null) {
            state = UserProfile(
              id: user.id,
              email: user.email ?? googleUser.email,
              displayName: googleUser.displayName ?? googleUser.email,
              avatarUrl: googleUser.photoUrl,
            );
            return;
          }
        }
      } catch (e) {
        debugPrint('Supabase sign-in error: $e');
      }
    }

    // Offline mode, or Supabase sign-in failed: use the Google profile alone.
    state = UserProfile(
      id: googleUser.id,
      email: googleUser.email,
      displayName: googleUser.displayName ?? googleUser.email,
      avatarUrl: googleUser.photoUrl,
    );
  }

  Future<void> signOut() async {
    await GoogleDriveService.instance.signOut();
    final client = SupabaseService.instance.client;
    if (client != null) {
      try {
        await client.auth.signOut();
      } catch (e) {
        debugPrint('Supabase sign-out error: $e');
      }
    }
    state = null;
  }

  void setDemoUser() {
    state = UserProfile.demo();
  }
}
