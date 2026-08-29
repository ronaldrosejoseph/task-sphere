import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/core/theme/app_theme.dart';
import 'package:task_sphere/providers/task_provider.dart';
import 'package:task_sphere/views/settings/settings_view.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: SettingsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('manage lanes tile opens the lane manager dialog', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Manage Kanban Lanes'));
    await tester.pumpAndSettle();

    expect(find.text('Add Lane'), findsOneWidget);
  });

  testWidgets('archived checkbox toggles the show-archived setting', (tester) async {
    final container = await pumpSettings(tester);

    expect(container.read(showArchivedTasksProvider), isFalse);

    await tester.tap(find.text('Show archived tasks on the board'));
    await tester.pumpAndSettle();

    expect(container.read(showArchivedTasksProvider), isTrue);

    await tester.tap(find.text('Show archived tasks on the board'));
    await tester.pumpAndSettle();

    expect(container.read(showArchivedTasksProvider), isFalse);
  });
}
