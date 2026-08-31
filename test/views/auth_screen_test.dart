import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/providers/auth_provider.dart';
import 'package:task_sphere/views/auth/auth_screen.dart';
import 'package:task_sphere/views/navigation/main_navigation_scaffold.dart';

void main() {
  testWidgets('signing out returns to the login screen', (tester) async {
    // Offline mode seeds the demo user, so the app opens on the board.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MainNavigationScaffold), findsOneWidget);
    expect(find.text('Sign in with Google'), findsNothing);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.byType(MainNavigationScaffold), findsNothing);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(container.read(authProvider), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed Google sign-in shows an error instead of doing nothing', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Offline mode seeds the demo user; sign out so the login screen shows.
    await container.read(authProvider.notifier).signOut();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    // The google_sign_in plugin has no platform implementation in tests, so
    // the flow fails; the failure must be visible, not silent.
    expect(find.textContaining('Google sign-in failed'), findsOneWidget);
    expect(container.read(authProvider), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the access-blocked banner when sign-in is rejected',
      (tester) async {
    const message = 'You are not part of any workspace. '
        'Please contact an admin to add you.';
    final container = ProviderContainer(
      overrides: [
        signInBlockedMessageProvider.overrideWith(
          () => _FixedSignInBlockedMessage(message),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Offline mode seeds the demo user; sign out so the login screen shows.
    await container.read(authProvider.notifier).signOut();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FixedSignInBlockedMessage extends SignInBlockedMessage {
  _FixedSignInBlockedMessage(this.message);

  final String? message;

  @override
  String? build() => message;
}
