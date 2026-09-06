import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/core/theme/app_theme.dart';
import 'package:task_sphere/models/lane.dart';
import 'package:task_sphere/models/task.dart';
import 'package:task_sphere/models/user_profile.dart';
import 'package:task_sphere/models/workspace.dart';
import 'package:task_sphere/providers/auth_provider.dart';
import 'package:task_sphere/providers/task_provider.dart';
import 'package:task_sphere/providers/workspace_provider.dart';
import 'package:task_sphere/views/settings/settings_view.dart';

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this.user);

  final UserProfile? user;

  @override
  UserProfile? build() => user;
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    ProviderContainer? container,
  }) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final effective = container ?? ProviderContainer();
    if (container == null) addTearDown(effective.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: effective,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: SettingsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return effective;
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

  testWidgets('on a narrow phone the auto-expiry header wraps without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: SettingsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The title must wrap over two lines rather than overflow the card.
    final header = find.text('Completed Tasks Auto-Expiry');
    expect(header, findsOneWidget);
    expect(tester.getSize(header).height, greaterThan(24));

    // The day chips still wrap in order with space between their rows.
    await tester.dragUntilVisible(
      find.text('Never'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
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
    // The demo workspace ships with Done / Wont Do pre-selected.
    expect(state.activeWorkspace.autoExpiryLaneIds, ['lane-4', 'lane-5']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping an auto-expiry lane chip persists the selection', (tester) async {
    final container = await pumpSettings(tester);

    // Deselect 'Done' (lane-4): the stored selection becomes explicit.
    await tester.tap(find.widgetWithText(FilterChip, 'Done'));
    await tester.pumpAndSettle();

    final state = container.read(activeWorkspaceProvider);
    expect(state.activeWorkspace.autoExpiryLaneIds, ['lane-5']);

    // Tap again to re-add it.
    await tester.tap(find.widgetWithText(FilterChip, 'Done'));
    await tester.pumpAndSettle();

    expect(
      container.read(activeWorkspaceProvider).activeWorkspace.autoExpiryLaneIds,
      unorderedEquals(['lane-4', 'lane-5']),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin can rename the workspace from Settings', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(
              id: 'demo-user-123',
              email: 'alex.admin@tasksphere.app',
              displayName: 'Alex',
            ),
          ),
        ),
        isDemoUserProvider.overrideWith((ref) => false),
      ],
    );
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

    expect(find.text('Workspace Name'), findsOneWidget);
    expect(find.text('Engineering & Design Team'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'XYZ Studio');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      container.read(activeWorkspaceProvider).activeWorkspace.name,
      'XYZ Studio',
    );
    // The settings tile shows the new name.
    expect(find.text('XYZ Studio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo mode hides the workspace rename control', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Default providers sign in the demo user (read-only sandbox).
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: SettingsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Workspace Name'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulling down on the settings list refreshes workspace and tasks', (tester) async {
    final workspace = Workspace(id: 'ws-s', name: 'Settings Team', adminId: 'a');
    final wsSpy = _RefreshSpyWorkspaceNotifier(
      WorkspaceState(
        activeWorkspace: workspace,
        allWorkspaces: [workspace],
        lanes: [KanbanLane(id: 'lane-1', workspaceId: 'ws-s', title: 'To Do')],
      ),
    );
    final taskSpy = _RefreshSpyTaskNotifier(const []);
    final container = ProviderContainer(
      overrides: [
        activeWorkspaceProvider.overrideWith(() => wsSpy),
        tasksProvider.overrideWith(() => taskSpy),
      ],
    );
    addTearDown(container.dispose);
    await pumpSettings(tester, container: container);

    await tester.fling(find.byType(ListView).first, const Offset(0, 600), 1000);
    await tester.pumpAndSettle();

    expect(wsSpy.reloads, 1);
    expect(taskSpy.reloads, 1);
    expect(tester.takeException(), isNull);
  });
}

class _RefreshSpyWorkspaceNotifier extends WorkspaceNotifier {
  _RefreshSpyWorkspaceNotifier(this.initialState);

  final WorkspaceState initialState;

  int reloads = 0;

  @override
  WorkspaceState build() => initialState;

  @override
  Future<void> loadInitialData() async => reloads++;
}

class _RefreshSpyTaskNotifier extends TaskNotifier {
  _RefreshSpyTaskNotifier(this.tasks);

  final List<TaskItem> tasks;

  int reloads = 0;

  @override
  List<TaskItem> build() => tasks;

  @override
  Future<void> reload() async => reloads++;
}
