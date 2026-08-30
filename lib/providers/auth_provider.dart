import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../core/services/google_auth_service.dart';
import '../core/services/supabase_service.dart';
import 'demo_mode_provider.dart';

final authProvider = NotifierProvider<AuthNotifier, UserProfile?>(AuthNotifier.new);

/// True when the signed-in user is the seeded demo sandbox user. The demo
/// session runs on in-memory repositories and blocks creations/invites;
/// real sign-ins use the live Supabase backend.
final isDemoUserProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  return user?.id == UserProfile.demoUserId;
});

class AuthNotifier extends Notifier<UserProfile?> {
  StreamSubscription<AuthState>? _authSub;

  @override
  UserProfile? build() {
    final client = SupabaseService.instance.client;
    if (client == null) {
      // No backend: offline builds enter the demo sandbox directly, while
      // demo builds stay on the login page until the demo button is clicked.
      return ref.read(demoModeProvider) ? null : UserProfile.demo();
    }
    // A client exists: restore any persisted session (covers the OAuth
    // redirect back on web and returning real users on the demo build) and
    // listen for future auth changes. First-time visitors still see the
    // login page; the demo sandbox stays opt-in via the demo button.

    ref.onDispose(() => _authSub?.cancel());
    _authSub = client.auth.onAuthStateChange.listen((event) {
      final user = event.session?.user;
      if (user != null) {
        final current = state;
        // Preserve a richer profile set by the idToken flow; still pick up
        // sessions that arrive after an OAuth redirect (web PKCE flow).
        if (current == null || current.id != user.id) {
          state = profileFromUser(user);
        }
      } else if (event.event == AuthChangeEvent.signedOut) {
        state = null;
      }
    });

    unawaited(restoreSession());
    return null;
  }

  /// Restores a persisted Supabase session after an app restart.
  Future<void> restoreSession() async {
    final client = SupabaseService.instance.client;
    if (client == null) return;
    final sessionUser = client.auth.currentUser;
    if (sessionUser == null) return;
    if (ref.mounted) {
      state = profileFromUser(sessionUser);
    }
  }

  Future<void> signInWithGoogle() async {
    final supabaseClient = SupabaseService.instance.client;

    if (kIsWeb && supabaseClient != null) {
      // google_sign_in does not expose an idToken on web; use the Supabase
      // PKCE redirect flow instead. The session arrives via onAuthStateChange
      // after the provider redirects back to the app.
      try {
        await supabaseClient.auth.signInWithOAuth(OAuthProvider.google);
      } catch (e) {
        debugPrint('Supabase web sign-in error: $e');
      }
      return;
    }

    final googleUser = await GoogleAuthService.instance.signIn();
    if (googleUser == null) return;

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
    // Web sign-ins go through the Supabase PKCE redirect and never use
    // google_sign_in; its plugin can hang on web when uninitialized, so
    // only disconnect the Google account on native platforms.
    if (!kIsWeb) {
      try {
        await GoogleAuthService.instance.signOut();
      } catch (e) {
        debugPrint('Google sign-out error: $e');
      }
    }
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

UserProfile profileFromUser(User user, {String? fallbackEmail}) {
  final metadata = user.userMetadata ?? const {};
  return UserProfile(
    id: user.id,
    email: user.email ?? fallbackEmail ?? '',
    displayName: (metadata['full_name'] as String?) ??
        (metadata['name'] as String?) ??
        user.email ??
        'User',
    avatarUrl: metadata['avatar_url'] as String?,
  );
}
