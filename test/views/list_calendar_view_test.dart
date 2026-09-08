import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/core/repositories/task_repository.dart';
import 'package:task_sphere/core/repositories/workspace_repository.dart';
import 'package:task_sphere/core/theme/app_theme.dart';
import 'package:task_sphere/models/lane.dart';
import 'package:task_sphere/models/task.dart';
import 'package:task_sphere/models/user_profile.dart';
import 'package:task_sphere/models/workspace.dart';
import 'package:task_sphere/providers/auth_provider.dart';
import 'package:task_sphere/providers/task_provider.dart';
import 'package:task_sphere/providers/workspace_provider.dart';
import 'package:task_sphere/views/list_calendar/list_calendar_view.dart';
import '../providers/repository_provider_test.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<(ProviderContainer, _RefreshSpyWorkspaceNotifier, _RefreshSpyTaskNotifier)>
      pumpListCalendar(WidgetTester tester) async {
    final workspace = Workspace(id: 'ws-l', name: 'List Team', adminId: 'a');
    final wsSpy = _RefreshSpyWorkspaceNotifier(
      WorkspaceState(
        activeWorkspace: workspace,
        allWorkspaces: [workspace],
        lanes: [
          KanbanLane(id: 'lane-1', workspaceId: 'ws-l', title: 'To Do'),
          KanbanLane(id: 'lane-2', workspaceId: 'ws-l', title: 'Done'),
        ],
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

    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: ListCalendarView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container, wsSpy, taskSpy);
  }

  testWidgets('shows the task list, calendar and archived tabs', (tester) async {
    await pumpListCalendar(tester);

    expect(find.text('Task List'), findsOneWidget);
    expect(find.text('Calendar View'), findsOneWidget);
    expect(find.text('Archived Tasks'), findsOneWidget);
    expect(find.text('To Do (0)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulling down on the task list refreshes workspace and tasks', (tester) async {
    final (_, wsSpy, taskSpy) = await pumpListCalendar(tester);

    // Task List is the default tab; the pull gesture at the top of the list
    // must trigger a refresh.
    await tester.fling(find.text('To Do (0)'), const Offset(0, 500), 1000);
    await tester.pumpAndSettle();

    expect(wsSpy.reloads, 1);
    expect(taskSpy.reloads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulling down on the empty archived page also refreshes', (tester) async {
    final (_, wsSpy, taskSpy) = await pumpListCalendar(tester);

    await tester.tap(find.text('Archived Tasks'));
    await tester.pumpAndSettle();

    // The empty state is scrollable so the pull gesture works there too.
    expect(find.text('No Archived Tasks'), findsOneWidget);
    await tester.fling(find.text('No Archived Tasks'), const Offset(0, 500), 1000);
    await tester.pumpAndSettle();

    expect(wsSpy.reloads, 1);
    expect(taskSpy.reloads, 1);
    expect(tester.takeException(), isNull);
  });

  group('Archive tab', () {
    Workspace expiryWorkspace() => Workspace(
          id: 'ws-a',
          name: 'Expiry',
          adminId: 'a',
          autoArchiveDays: 14,
          autoExpiryLaneIds: const ['lane-2'],
        );

    Future<ProviderContainer> pumpArchiveBoard(
      WidgetTester tester, {
      required FakeTaskRepository taskRepo,
    }) async {
      final ws = expiryWorkspace();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(
              UserProfile(id: 'a', email: 'a@x.com', displayName: 'A'),
            ),
          ),
          workspaceRepositoryProvider.overrideWith(
            (ref) => FakeWorkspaceRepository(),
          ),
          taskRepositoryProvider.overrideWith((ref) => taskRepo),
          activeWorkspaceProvider.overrideWith(
            () => _FixedWorkspaceNotifier(WorkspaceState(
              activeWorkspace: ws,
              allWorkspaces: [ws],
              lanes: [
                KanbanLane(id: 'lane-1', workspaceId: ws.id, title: 'To Do', orderIndex: 0),
                KanbanLane(id: 'lane-2', workspaceId: ws.id, title: 'Done', orderIndex: 1),
              ],
            )),
          ),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: ListCalendarView()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('auto-expired tasks appear only in the Archive tab', (tester) async {
      final repo = FakeTaskRepository()
        ..stored.addAll([
          TaskItem(
            id: 'expired-1',
            workspaceId: 'ws-a',
            laneId: 'lane-2',
            title: 'Expired ticket',
            createdAt: DateTime.now().subtract(const Duration(days: 30)),
          ),
          TaskItem(
            id: 'active-1',
            workspaceId: 'ws-a',
            laneId: 'lane-1',
            title: 'Active ticket',
            createdAt: DateTime.now().subtract(const Duration(days: 2)),
          ),
        ]);
      await pumpArchiveBoard(tester, taskRepo: repo);

      // The task list keeps only active tasks; the auto-expired one is not
      // flagged archived yet still belongs to the archive.
      expect(find.text('Active ticket'), findsOneWidget);
      expect(find.text('Expired ticket'), findsNothing);

      await tester.tap(find.text('Archived Tasks'));
      await tester.pumpAndSettle();

      expect(find.text('Expired ticket'), findsOneWidget);
      expect(find.text('Active ticket'), findsNothing);
      expect(find.text('Restore'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('restoring an auto-expired task moves it to the first active lane',
        (tester) async {
      final repo = FakeTaskRepository()
        ..stored.add(TaskItem(
          id: 'expired-1',
          workspaceId: 'ws-a',
          laneId: 'lane-2',
          title: 'Expired ticket',
          createdAt: DateTime.now().subtract(const Duration(days: 30)),
        ));
      final container = await pumpArchiveBoard(tester, taskRepo: repo);

      await tester.tap(find.text('Archived Tasks'));
      await tester.pumpAndSettle();
      expect(find.text('Expired ticket'), findsOneWidget);

      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      // The ticket is back on the active board in the non-expiry lane.
      final restored = container
          .read(tasksProvider)
          .firstWhere((t) => t.id == 'expired-1');
      expect(restored.isArchived, isFalse);
      expect(restored.laneId, 'lane-1');

      // The archive is empty again and the task list shows the ticket.
      expect(find.text('No Archived Tasks'), findsOneWidget);
      await tester.tap(find.text('Task List'));
      await tester.pumpAndSettle();
      expect(find.text('Expired ticket'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this.user);

  final UserProfile? user;

  @override
  UserProfile? build() => user;
}

class _FixedWorkspaceNotifier extends WorkspaceNotifier {
  _FixedWorkspaceNotifier(this.initialState);

  final WorkspaceState initialState;

  @override
  WorkspaceState build() => initialState;
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
