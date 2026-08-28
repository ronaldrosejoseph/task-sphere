import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import '../core/services/google_drive_service.dart';
import '../core/services/supabase_service.dart';

final authProvider = StateNotifierProvider<AuthNotifier, UserProfile?>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<UserProfile?> {
  AuthNotifier() : super(UserProfile.demo());

  Future<void> signInWithGoogle() async {
    final googleUser = await GoogleDriveService.instance.signIn();
    if (googleUser != null) {
      state = UserProfile(
        id: googleUser.id,
        email: googleUser.email,
        displayName: googleUser.displayName ?? googleUser.email,
        avatarUrl: googleUser.photoUrl,
      );
    }
  }

  Future<void> signOut() async {
    await GoogleDriveService.instance.signOut();
    if (SupabaseService.instance.isInitialized) {
      await SupabaseService.instance.client?.auth.signOut();
    }
    state = null;
  }

  void setDemoUser() {
    state = UserProfile.demo();
  }
}
