import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/core/theme/app_theme.dart';
import 'package:task_sphere/models/task.dart';
import 'package:task_sphere/providers/demo_mode_provider.dart';
import 'package:task_sphere/providers/task_provider.dart';
import 'package:task_sphere/providers/workspace_provider.dart';
import 'package:task_sphere/views/kanban/kanban_view.dart';

class _EmptyWorkspaceNotifier extends WorkspaceNotifier {
  @override
  WorkspaceState build() => WorkspaceState.empty();
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
      await tester.tap(find.text('alex.admin').last);
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
        ],
      );
      addTearDown(container.dispose);
      await pumpBoard(tester, container: container);

      expect(find.text('No Workspace Yet'), findsOneWidget);
      expect(find.text('Create Workspace'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Kanban interactions', () {
    testWidgets('floating action button opens the new task modal', (tester) async {
      await pumpBoard(tester);

      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Create New Task'), findsOneWidget);
      expect(find.text('Save Task'), findsOneWidget);
    });

    testWidgets('demo mode hides all task creation controls', (tester) async {
      final container = ProviderContainer(
        overrides: [demoModeProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      await pumpBoard(tester, container: container);

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

    testWidgets('dragging a card onto another lane moves the task', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pumpBoard(tester, container: container);

      final card = find.text('Design Dark Mode Glassmorphic UI System');
      expect(card, findsOneWidget);

      // To Do is the leftmost column, one lane width to the left of In Progress.
      final gesture = await tester.startGesture(tester.getCenter(card));
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
    });
  });
}
