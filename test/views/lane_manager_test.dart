import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/models/task.dart';
import 'package:task_sphere/providers/task_provider.dart';
import 'package:task_sphere/providers/workspace_provider.dart';
import 'package:task_sphere/views/kanban/widgets/lane_manager_dialog.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(activeWorkspaceProvider.notifier)
        .addLane('In Review', const Color(0xFFEC4899));
    final laneId = container.read(activeWorkspaceProvider).lanes.last.id;
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

  testWidgets('deleting a custom lane asks for confirmation', (tester) async {
    final container = await pumpDialog(tester);

    // Only the custom lane has a delete button.
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await tester.ensureVisible(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete "In Review"?'), findsOneWidget);
    expect(
      find.text('1 task(s) in this lane will be permanently deleted.'),
      findsOneWidget,
    );

    // Cancel keeps lane and task.
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

  testWidgets('confirming deletes the lane and its tasks', (tester) async {
    final container = await pumpDialog(tester);

    await tester.ensureVisible(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Lane'));
    await tester.pumpAndSettle();

    expect(
      container.read(activeWorkspaceProvider).lanes.any((l) => l.title == 'In Review'),
      isFalse,
    );
    expect(
      container.read(tasksProvider).any((t) => t.id == 'custom-task'),
      isFalse,
    );
  });
}
