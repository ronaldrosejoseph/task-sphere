import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/models/task.dart';
import 'package:task_sphere/models/user_profile.dart';
import 'package:task_sphere/providers/auth_provider.dart';
import 'package:task_sphere/providers/task_provider.dart';
import 'package:task_sphere/providers/workspace_provider.dart';
import 'package:task_sphere/views/kanban/widgets/lane_manager_dialog.dart';

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

  Future<ProviderContainer> pumpDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        // A real signed-in user so task creation works (the demo sandbox
        // user cannot create tasks).
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'u-1', email: 'u@x.com', displayName: 'U'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(activeWorkspaceProvider.notifier)
        .addLane('In Review', const Color(0xFFEC4899));
    // New lanes are prepended, so the added lane is now first.
    final laneId = container.read(activeWorkspaceProvider).lanes.first.id;
    container.read(tasksProvider.notifier).addTask(TaskItem(
          id: 'custom-task',
          workspaceId: 'ws-demo-001',
          laneId: laneId,
          title: 'Task in custom lane',
        ));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: LaneManagerDialog())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  // Every lane now has a delete icon, so target the specific lane's card.
  Future<void> tapDelete(WidgetTester tester, String laneTitle) async {
    final deleteIcon = find.descendant(
      of: find.widgetWithText(Card, laneTitle),
      matching: find.byIcon(Icons.delete_outline),
    );
    await tester.ensureVisible(deleteIcon);
    await tester.pumpAndSettle();
    await tester.tap(deleteIcon);
    await tester.pumpAndSettle();
  }

  testWidgets('deleting a lane with tasks warns and requires moving them first', (tester) async {
    final container = await pumpDialog(tester);

    await tapDelete(tester, 'In Review');

    expect(find.text('Delete "In Review"?'), findsOneWidget);
    expect(
      find.textContaining('still contains 1 task(s)'),
      findsOneWidget,
    );
    expect(find.text('Move tasks to'), findsOneWidget);

    // Cancel keeps the lane and the task untouched.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      container.read(activeWorkspaceProvider).lanes.any((l) => l.title == 'In Review'),
      isTrue,
    );
    expect(
      container.read(tasksProvider).any((t) => t.id == 'custom-task'),
      isTrue,
    );
  });

  testWidgets('confirming moves the tasks to the chosen lane then deletes', (tester) async {
    final container = await pumpDialog(tester);
    final toDoLaneId = container
        .read(activeWorkspaceProvider)
        .lanes
        .firstWhere((l) => l.title == 'To Do')
        .id;

    await tapDelete(tester, 'In Review');

    // Default target is the first other lane (To Do).
    expect(find.text('To Do'), findsWidgets);
    await tester.tap(find.text('Move Tasks & Delete'));
    await tester.pumpAndSettle();

    expect(
      container.read(activeWorkspaceProvider).lanes.any((l) => l.title == 'In Review'),
      isFalse,
    );
    final moved = container
        .read(tasksProvider)
        .firstWhere((t) => t.id == 'custom-task');
    expect(moved.laneId, toDoLaneId);
  });

  testWidgets('default lanes can be deleted too', (tester) async {
    final container = await pumpDialog(tester);

    // 'To Do' is a default lane holding the seeded task-102, so the move
    // dialog is shown; the default target is the first other lane (In Review).
    await tapDelete(tester, 'To Do');

    expect(find.text('Delete "To Do"?'), findsOneWidget);
    expect(find.textContaining('still contains'), findsOneWidget);
    await tester.tap(find.text('Move Tasks & Delete'));
    await tester.pumpAndSettle();

    expect(
      container.read(activeWorkspaceProvider).lanes.any((l) => l.title == 'To Do'),
      isFalse,
    );
    final moved = container.read(tasksProvider).firstWhere((t) => t.id == 'task-102');
    expect(moved.laneId, container.read(activeWorkspaceProvider).lanes.first.id);
  });

  testWidgets('deleting an empty lane asks for a simple confirmation', (tester) async {
    final container = await pumpDialog(tester);
    container
        .read(activeWorkspaceProvider.notifier)
        .addLane('Empty Lane', const Color(0xFF06B6D4));

    await tester.pumpAndSettle();

    // Delete the empty lane first (the last one in the list).
    final emptyLaneCard = find.widgetWithText(Card, 'Empty Lane');
    await tester.dragUntilVisible(
      emptyLaneCard,
      find.byType(ReorderableListView),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: emptyLaneCard, matching: find.byIcon(Icons.delete_outline)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete "Empty Lane"?'), findsOneWidget);
    expect(find.text('This lane will be removed.'), findsOneWidget);
    await tester.tap(find.text('Delete Lane'));
    await tester.pumpAndSettle();

    expect(
      container.read(activeWorkspaceProvider).lanes.any((l) => l.title == 'Empty Lane'),
      isFalse,
    );
    expect(
      container.read(activeWorkspaceProvider).lanes.any((l) => l.title == 'In Review'),
      isTrue,
    );
  });

  testWidgets('editing a lane requires a non-empty name', (tester) async {
    await pumpDialog(tester);

    final toDoCard = find.widgetWithText(Card, 'To Do');
    final toDoEditIcon =
        find.descendant(of: toDoCard, matching: find.byIcon(Icons.edit));
    await tester.ensureVisible(toDoEditIcon);
    await tester.pumpAndSettle();
    await tester.tap(toDoEditIcon);
    await tester.pumpAndSettle();

    expect(find.text('Edit To Do'), findsOneWidget);

    // The edit field is the one labeled 'Column Title'.
    final editField = find.ancestor(
      of: find.text('Column Title'),
      matching: find.byType(TextField),
    );
    expect(editField, findsOneWidget);

    // Clearing the title shows the error and disables Save.
    await tester.enterText(editField, '');
    await tester.pumpAndSettle();
    expect(find.text('Lane name cannot be empty'), findsOneWidget);
    final saveButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Save'),
    );
    expect(saveButton.onPressed, isNull);

    // A valid name enables Save and renames the lane.
    await tester.enterText(editField, 'Backlog');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Backlog'),
      findsWidgets,
    );
  });
}
