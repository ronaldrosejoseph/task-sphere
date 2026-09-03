import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/core/theme/app_theme.dart';
import 'package:task_sphere/providers/workspace_provider.dart';
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

  testWidgets('auto-expiry chips render in dark mode', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: SettingsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['7 Days', '14 Days', '30 Days', '90 Days', 'Never']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('manage lanes tile opens the lane manager dialog', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Manage Kanban Lanes'));
    await tester.pumpAndSettle();

    expect(find.text('Add Lane'), findsOneWidget);
  });

  testWidgets('archived checkbox toggles the show-archived setting', (tester) async {
    final container = await pumpSettings(tester);

    expect(
      container.read(activeWorkspaceProvider).activeWorkspace.showArchivedTasks,
      isFalse,
    );

    await tester.tap(find.text('Show archived tasks on the board'));
    await tester.pumpAndSettle();

    expect(
      container.read(activeWorkspaceProvider).activeWorkspace.showArchivedTasks,
      isTrue,
    );

    await tester.tap(find.text('Show archived tasks on the board'));
    await tester.pumpAndSettle();

    expect(
      container.read(activeWorkspaceProvider).activeWorkspace.showArchivedTasks,
      isFalse,
    );
  });

  testWidgets('auto-expiry lane chips render with Done/Wont Do pre-selected', (tester) async {
    final container = await pumpSettings(tester);

    for (final label in ['To Do', 'In Progress', 'Partially Done', 'Done', 'Wont Do']) {
      expect(find.widgetWithText(FilterChip, label), findsOneWidget);
    }

    final state = container.read(activeWorkspaceProvider);
    // Unconfigured workspace: the chips reflect the legacy title fallback.
    expect(state.activeWorkspace.autoExpiryLaneIds, isNull);
    expect(state.activeWorkspace.resolvedAutoExpiryLaneIds(state.lanes),
        ['lane-4', 'lane-5']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping an auto-expiry lane chip persists the selection', (tester) async {
    final container = await pumpSettings(tester);

    // Deselect 'Done' (lane-4): the stored selection becomes explicit.
    await tester.tap(find.widgetWithText(FilterChip, 'Done'));
    await tester.pumpAndSettle();

    final state = container.read(activeWorkspaceProvider);
    expect(state.activeWorkspace.autoExpiryLaneIds, ['lane-5']);
    expect(state.activeWorkspace.resolvedAutoExpiryLaneIds(state.lanes), ['lane-5']);

    // Tap again to re-add it.
    await tester.tap(find.widgetWithText(FilterChip, 'Done'));
    await tester.pumpAndSettle();

    expect(
      container.read(activeWorkspaceProvider).activeWorkspace.autoExpiryLaneIds,
      unorderedEquals(['lane-4', 'lane-5']),
    );
    expect(tester.takeException(), isNull);
  });
}
