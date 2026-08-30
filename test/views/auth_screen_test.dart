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
}
