import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:task_sphere/models/user_profile.dart';
import 'package:task_sphere/providers/auth_provider.dart';

void main() {
  group('AuthNotifier in offline mode (Supabase not initialized)', () {
    test('starts with the demo user so the app opens directly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(authProvider)?.id, 'demo-user-123');
    });

    test('setDemoUser restores the demo profile', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(authProvider.notifier).setDemoUser();
      expect(container.read(authProvider)?.email, 'alex.admin@tasksphere.app');
      expect(container.read(authProvider)?.displayName, 'Alex Morgan (Admin)');
    });

    test('signOut clears the user', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(authProvider.notifier).signOut();
      expect(container.read(authProvider), isNull);
    });

    test('signInWithGoogle without a platform keeps current state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(authProvider.notifier);

      // google_sign_in plugin is unavailable in tests, so sign-in fails
      // gracefully and the demo profile remains.
      await notifier.signInWithGoogle();
      expect(container.read(authProvider), isNotNull);
    });
  });

  test('UserProfile demo factory is stable', () {
    final first = UserProfile.demo();
    final second = UserProfile.demo();
    expect(first.id, second.id);
    expect(first.email, second.email);
    expect(first.displayName, second.displayName);
  });

  group('profileFromUser', () {
    test('extracts identity and metadata from a Supabase user', () {
      final user = User.fromJson({
        'id': 'uid-1',
        'email': 'alex@example.com',
        'user_metadata': {'full_name': 'Alex Morgan', 'avatar_url': 'http://img'},
      })!;
      final profile = profileFromUser(user);
      expect(profile.id, 'uid-1');
      expect(profile.email, 'alex@example.com');
      expect(profile.displayName, 'Alex Morgan');
      expect(profile.avatarUrl, 'http://img');
    });

    test('falls back to email as display name when metadata is missing', () {
      final user = User.fromJson({'id': 'uid-2', 'email': 'bob@example.com'})!;
      final profile = profileFromUser(user);
      expect(profile.displayName, 'bob@example.com');
      expect(profile.avatarUrl, isNull);
      expect(profile.email, 'bob@example.com');
    });
  });
}
