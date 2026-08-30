import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/models/task.dart';
import 'package:task_sphere/models/user_profile.dart';
import 'package:task_sphere/providers/auth_provider.dart';
import 'package:task_sphere/providers/task_provider.dart';
import 'package:task_sphere/views/task_detail/task_detail_modal.dart';

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

  Future<ProviderContainer> pumpModal(
    WidgetTester tester, {
    TaskItem? task,
    Size size = const Size(360, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Default providers provide the demo workspace with seeded tasks.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: TaskDetailModal(task: task)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('create mode renders without overflow on a phone-size screen', (tester) async {
    await pumpModal(tester);

    expect(find.text('Create New Task'), findsOneWidget);
    expect(find.text('Start Timer'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Regression: the Start Timer button used to sit next to the tracker
    // label and overflow; on a phone it wraps to its own line.
    final buttonTop = tester.getTopLeft(find.widgetWithText(ElevatedButton, 'Start Timer')).dy;
    final labelBottom = tester.getBottomLeft(find.text('Time Tracker')).dy;
    expect(buttonTop, greaterThan(labelBottom));
  });

  testWidgets('edit mode shows the tracker total without overflow', (tester) async {
    await pumpModal(
      tester,
      task: TaskItem(
        id: 'task-edit',
        workspaceId: 'ws-demo-001',
        laneId: 'lane-1',
        title: 'Edit me',
        loggedSeconds: 3900,
      ),
    );

    expect(find.text('Task Details'), findsOneWidget);
    expect(find.textContaining('Total Logged:'), findsOneWidget);
    expect(find.text('Start Timer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving a new task persists the auth user id as createdBy', (tester) async {
    // Pushed on a real dialog route so the save flow can pop it.
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'user-abc', email: 'alex@x.com', displayName: 'Alex'),
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
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog(
                    context: ctx,
                    builder: (_) => const TaskDetailModal(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Persisted ticket');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Task'));
    await tester.pumpAndSettle();

    final tasks = container.read(tasksProvider);
    expect(tasks.first.title, 'Persisted ticket');
    // Regression: created_by is a UUID column; the display name used to be
    // sent, failing the insert on the real database.
    expect(tasks.first.createdBy, 'user-abc');
    expect(find.byType(TaskDetailModal), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a wide screen the timer button stays on the tracker row', (tester) async {
    await pumpModal(tester, size: const Size(900, 1600));

    final buttonCenter = tester.getCenter(find.widgetWithText(ElevatedButton, 'Start Timer')).dy;
    final labelCenter = tester.getCenter(find.text('Time Tracker')).dy;
    expect((buttonCenter - labelCenter).abs(), lessThan(20));
    expect(tester.takeException(), isNull);
  });
}
