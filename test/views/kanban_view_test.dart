import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
import 'package:task_sphere/views/kanban/kanban_view.dart';

class _EmptyWorkspaceNotifier extends WorkspaceNotifier {
  @override
  WorkspaceState build() => WorkspaceState.empty();
}

class _FixedWorkspaceNotifier extends WorkspaceNotifier {
  _FixedWorkspaceNotifier(this.initialState);

  final WorkspaceState initialState;

  @override
  WorkspaceState build() => initialState;
}

class _FixedTaskNotifier extends TaskNotifier {
  _FixedTaskNotifier(this.tasks);

  final List<TaskItem> tasks;

  @override
  List<TaskItem> build() => tasks;
}

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

  Future<void> pumpBoard(
    WidgetTester tester, {
    ProviderContainer? container,
  }) async {
    tester.view.physicalSize = const Size(2400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final app = MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: KanbanView()),
    );

    if (container != null) {
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: app),
      );
    } else {
      await tester.pumpWidget(ProviderScope(child: app));
    }
    await tester.pumpAndSettle();
  }

  group('Kanban board rendering', () {
    testWidgets('renders all five default lanes with headers', (tester) async {
      await pumpBoard(tester);

      for (final lane in ['To Do', 'In Progress', 'Partially Done', 'Done', 'Wont Do']) {
        expect(find.text(lane), findsOneWidget);
      }
    });

    testWidgets('renders seeded task cards on the board', (tester) async {
      await pumpBoard(tester);

      expect(find.text('Design Dark Mode Glassmorphic UI System'), findsOneWidget);
      expect(find.text('Implement Supabase Realtime WebSockets'), findsOneWidget);
      expect(find.text('Supabase Storage File Attachment Integration'), findsOneWidget);
      expect(find.text('Setup Flutter Multi-Platform Target Configuration'), findsOneWidget);
    });

    testWidgets('task cards label and color their date chips', (tester) async {
      await pumpBoard(tester);

      // One labeled Created chip per visible card (the archived task is
      // hidden); the seeded dates are relative to now, so the date itself is
      // not asserted.
      expect(find.textContaining('Created '), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides archived tasks by default', (tester) async {
      await pumpBoard(tester);

      expect(find.text('Legacy MySQL Server Backend'), findsNothing);
    });
  });

  group('Kanban filters', () {
    testWidgets('narrow screens stack search above the filters', (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: KanbanView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      expect(find.text('All Priorities'), findsOneWidget);
      expect(find.text('All Assignees'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Search spans the full width (roughly the screen width minus padding).
      final searchWidth = tester.getSize(searchField).width;
      expect(searchWidth, greaterThan(400));

      // Both filters stretch to equal widths across the second line.
      final priorityWidth = tester.getSize(find.byType(DropdownButton<TaskPriority?>)).width;
      final assigneeWidth = tester.getSize(find.byType(DropdownButton<String?>)).width;
      expect(priorityWidth, assigneeWidth);
      expect(priorityWidth, greaterThan(180));
    });

    testWidgets('search filter narrows tasks by title', (tester) async {
      await pumpBoard(tester);

      await tester.enterText(find.byType(TextField).first, 'realtime');
      await tester.pumpAndSettle();

      expect(find.text('Implement Supabase Realtime WebSockets'), findsOneWidget);
      expect(find.text('Design Dark Mode Glassmorphic UI System'), findsNothing);
      expect(find.text('Supabase Storage File Attachment Integration'), findsNothing);
    });

    testWidgets('priority filter keeps only the selected priority', (tester) async {
      await pumpBoard(tester);

      await tester.tap(find.text('All Priorities'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Urgent').last);
      await tester.pumpAndSettle();

      expect(find.text('Design Dark Mode Glassmorphic UI System'), findsOneWidget);
      expect(find.text('Implement Supabase Realtime WebSockets'), findsNothing);
    });

    testWidgets('assignee filter keeps only tasks of the selected member', (tester) async {
      await pumpBoard(tester);

      await tester.tap(find.text('All Assignees'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex Morgan').last);
      await tester.pumpAndSettle();

      expect(find.text('Implement Supabase Realtime WebSockets'), findsOneWidget);
      expect(find.text('Design Dark Mode Glassmorphic UI System'), findsNothing);
    });

    testWidgets('shows archived tasks when the setting is enabled', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpBoard(tester, container: container);

      container.read(activeWorkspaceProvider.notifier).updateShowArchivedTasks(true);
      await tester.pump();
      // Advance past the entrance animation's delay timer.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Legacy MySQL Server Backend'), findsOneWidget);
    });
  });

  group('No-workspace state', () {
    testWidgets('shows a create prompt and hides the FAB when no workspace exists', (tester) async {
      final container = ProviderContainer(
        overrides: [
          activeWorkspaceProvider.overrideWith(() => _EmptyWorkspaceNotifier()),
          authProvider.overrideWith(
            () => _FixedAuthNotifier(
              UserProfile(id: 'u-1', email: 'u@x.com', displayName: 'U'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await pumpBoard(tester, container: container);

      expect(find.text('No Workspace Yet'), findsOneWidget);
      expect(find.text('Create Workspace'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides the create button when workspace creation is denied', (tester) async {
      final container = ProviderContainer(
        overrides: [
          activeWorkspaceProvider.overrideWith(() => _EmptyWorkspaceNotifier()),
          canCreateWorkspaceProvider.overrideWith((ref) async => false),
        ],
      );
      addTearDown(container.dispose);
      await pumpBoard(tester, container: container);

      expect(find.text('No Workspace Yet'), findsOneWidget);
      expect(find.text('Create Workspace'), findsNothing);
      expect(
        find.text('Contact an admin for access to create a workspace.'),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Kanban interactions', () {
    testWidgets('floating action button opens the new task modal', (tester) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(
              UserProfile(id: 'u-1', email: 'u@x.com', displayName: 'U'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await pumpBoard(tester, container: container);

      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Create New Task'), findsOneWidget);
      expect(find.text('Save Task'), findsOneWidget);
    });

    testWidgets('demo user sees no task creation controls', (tester) async {
      // Default providers sign in the demo user (no Supabase client in tests).
      await pumpBoard(tester);

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a task card opens the detail modal', (tester) async {
      await pumpBoard(tester);

      await tester.tap(find.text('Design Dark Mode Glassmorphic UI System'));
      await tester.pumpAndSettle();

      expect(find.text('Task Details'), findsOneWidget);
      expect(find.text('Save Task'), findsOneWidget);
    });

    testWidgets('on touch devices a long press drags a card onto another lane', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpBoard(tester, container: container);

      final card = find.text('Design Dark Mode Glassmorphic UI System');
      expect(card, findsOneWidget);

      // To Do is the leftmost column, one lane width to the left of In
      // Progress. Touch platforms only start a drag after a long press, so
      // scrolling the board never moves a card by accident.
      final gesture = await tester.startGesture(tester.getCenter(card));
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final moved = container
          .read(tasksProvider)
          .firstWhere((t) => t.id == 'task-101');
      expect(moved.laneId, 'lane-1');

      // The move lands on the ticket's activity feed with the actor's
      // display name ('Alex Morgan', the demo member alias, not the email).
      final logs = container.read(activityLogsProvider);
      expect(logs.first.taskId, 'task-101');
      expect(logs.first.action, startsWith('Moved from'));
      expect(logs.first.userName, 'Alex Morgan');
    });

    testWidgets('scrolling the board on touch devices does not move a card', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpBoard(tester, container: container);

      final card = find.text('Design Dark Mode Glassmorphic UI System');
      final gesture = await tester.startGesture(tester.getCenter(card));
      // A quick scroll gesture below the long-press duration.
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // The task stayed in its lane; only the long press starts a drag.
      final unchanged = container
          .read(tasksProvider)
          .firstWhere((t) => t.id == 'task-101');
      expect(unchanged.laneId, 'lane-2');
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop mice drag a card immediately without a long press', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpBoard(tester, container: container);

      final card = find.text('Design Dark Mode Glassmorphic UI System');
      final gesture = await tester.startGesture(
        tester.getCenter(card),
        kind: PointerDeviceKind.mouse,
      );
      // The drag starts as soon as the mouse moves, before any long-press
      // timeout could fire.
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final moved = container
          .read(tasksProvider)
          .firstWhere((t) => t.id == 'task-101');
      expect(moved.laneId, 'lane-1');

      // The binding asserts foundation debug variables are reset before the
      // test body ends, so the override must be cleared here, not in a
      // teardown.
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a touch pointer switches the board to long-press drag on desktop', (tester) async {
      // Regression: Chrome mobile emulation sends touch pointers while the
      // browser still reports a desktop OS, so platform checks alone were
      // not enough to stop accidental moves.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpBoard(tester, container: container);

      final card = find.text('Design Dark Mode Glassmorphic UI System');

      // A first touch pointer (as mobile emulation sends) flips the board
      // into long-press mode.
      final tap = await tester.startGesture(tester.getCenter(card));
      await tester.pump();
      await tap.up();
      await tester.pumpAndSettle();

      // A quick scroll below the long-press duration must not move the card.
      final gesture = await tester.startGesture(tester.getCenter(card));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final unchanged = container
          .read(tasksProvider)
          .firstWhere((t) => t.id == 'task-101');
      expect(unchanged.laneId, 'lane-2');
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('Kanban auto-expiry lane selection', () {
    Workspace ws({List<String>? autoExpiryLaneIds}) => Workspace(
          id: 'ws-custom',
          name: 'Custom',
          adminId: 'u-1',
          autoArchiveDays: 14,
          autoExpiryLaneIds: autoExpiryLaneIds ?? const [],
        );

    TaskItem oldTask(String laneId, {String? title}) => TaskItem(
          id: 't-$laneId',
          workspaceId: 'ws-custom',
          laneId: laneId,
          title: title ?? 'Old completed task',
          createdAt: DateTime.now().subtract(const Duration(days: 30)),
        );

    Future<void> pumpCustomBoard(
      WidgetTester tester, {
      required Workspace workspace,
      required List<KanbanLane> lanes,
      required List<TaskItem> tasks,
    }) async {
      final container = ProviderContainer(
        overrides: [
          activeWorkspaceProvider.overrideWith(
            () => _FixedWorkspaceNotifier(WorkspaceState(
              activeWorkspace: workspace,
              allWorkspaces: [workspace],
              lanes: lanes,
            )),
          ),
          tasksProvider.overrideWith(() => _FixedTaskNotifier(tasks)),
        ],
      );
      addTearDown(container.dispose);
      await pumpBoard(tester, container: container);
    }

    testWidgets('stored lane ids auto-hide tasks even after a lane rename',
        (tester) async {
      await pumpCustomBoard(
        tester,
        workspace: ws(autoExpiryLaneIds: ['lane-f']),
        lanes: [
          KanbanLane(id: 'lane-o', workspaceId: 'ws-custom', title: 'Open'),
          // Renamed away from 'Done': the selection is by lane id, so the
          // rename does not disable auto-expiry for this lane.
          KanbanLane(id: 'lane-f', workspaceId: 'ws-custom', title: 'Finished'),
        ],
        tasks: [oldTask('lane-f', title: 'Renamed done task')],
      );

      expect(find.text('Renamed done task'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty selection disables auto-expiry even for Done/Wont Do lanes',
        (tester) async {
      await pumpCustomBoard(
        tester,
        workspace: ws(autoExpiryLaneIds: []),
        lanes: [
          KanbanLane(id: 'lane-d', workspaceId: 'ws-custom', title: 'Done'),
          KanbanLane(id: 'lane-w', workspaceId: 'ws-custom', title: 'Wont Do'),
        ],
        tasks: [oldTask('lane-d')],
      );

      expect(find.text('Old completed task'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a workspace without a selection keeps old tasks visible',
        (tester) async {
      // Auto-expiry is off until an admin picks lanes in Settings; there is
      // no implicit Done/Wont Do default for unconfigured workspaces.
      await pumpCustomBoard(
        tester,
        workspace: ws(),
        lanes: [
          KanbanLane(id: 'lane-d', workspaceId: 'ws-custom', title: 'Done'),
          KanbanLane(id: 'lane-w', workspaceId: 'ws-custom', title: 'Wont Do'),
        ],
        tasks: [oldTask('lane-d', title: 'Old done task')],
      );

      expect(find.text('Old done task'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
