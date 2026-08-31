import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/core/repositories/task_repository.dart';
import 'package:task_sphere/core/services/supabase_service.dart';
import 'package:task_sphere/models/task.dart';
import 'package:task_sphere/models/task_comment.dart';
import 'package:task_sphere/models/user_profile.dart';
import 'package:task_sphere/providers/auth_provider.dart';
import 'package:task_sphere/providers/task_provider.dart';
import 'package:task_sphere/views/task_detail/task_detail_modal.dart';
import '../providers/repository_provider_test.dart' show FakeTaskRepository;

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
    ProviderContainer? container,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Default providers provide the demo workspace with seeded tasks.
    final effectiveContainer = container ?? ProviderContainer();
    if (container == null) addTearDown(effectiveContainer.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: effectiveContainer,
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: TaskDetailModal(task: task)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return effectiveContainer;
  }

  ProviderContainer memberContainer() => ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(
              UserProfile(
                id: 'user-456',
                email: 'sarah.designer@tasksphere.app',
                displayName: 'Sarah',
              ),
            ),
          ),
        ],
      );

  ProviderContainer adminContainer() => ProviderContainer(
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

  final adminTicket = TaskItem(
    id: 't-admin',
    workspaceId: 'ws-demo-001',
    laneId: 'lane-1',
    title: 'Admin ticket',
    description: 'Made by the admin',
    createdBy: 'demo-user-123',
  );

  final ownTicket = TaskItem(
    id: 't-own',
    workspaceId: 'ws-demo-001',
    laneId: 'lane-1',
    title: 'My ticket',
    description: 'Made by me',
    createdBy: 'user-456',
  );

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

  group('ticket permissions', () {
    testWidgets('members cannot edit title/description of admin tickets and cannot delete', (tester) async {
      final container = memberContainer();
      addTearDown(container.dispose);
      await pumpModal(tester, task: adminTicket, container: container);

      expect(tester.widget<TextField>(find.byType(TextField).first).readOnly, isTrue);
      expect(tester.widget<TextField>(find.byType(TextField).at(1)).readOnly, isTrue);
      expect(find.textContaining('Only the creator or an admin'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('members can edit their own tickets but still cannot delete', (tester) async {
      final container = memberContainer();
      addTearDown(container.dispose);
      await pumpModal(tester, task: ownTicket, container: container);

      expect(tester.widget<TextField>(find.byType(TextField).first).readOnly, isFalse);
      expect(tester.widget<TextField>(find.byType(TextField).at(1)).readOnly, isFalse);
      expect(find.textContaining('Only the creator or an admin'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('admins can edit and delete any ticket', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpModal(tester, task: adminTicket, container: container);

      expect(tester.widget<TextField>(find.byType(TextField).first).readOnly, isFalse);
      expect(tester.widget<TextField>(find.byType(TextField).at(1)).readOnly, isFalse);
      expect(find.textContaining('Only the creator or an admin'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('modal sizing', () {
    testWidgets('on a phone the dialog fills the screen instead of the default 40px insets', (tester) async {
      await pumpModal(tester);

      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(
        dialog.insetPadding,
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a wide screen the dialog keeps the default insets', (tester) async {
      await pumpModal(tester, size: const Size(900, 1600));

      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(
        dialog.insetPadding,
        const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('description readability', () {
    final longDescription = 'A' * 500;

    testWidgets('read-only long description grows to show all of the content', (tester) async {
      final container = memberContainer();
      addTearDown(container.dispose);
      // Tall viewport so the full grown field stays on screen.
      await pumpModal(
        tester,
        task: adminTicket.copyWith(description: longDescription),
        container: container,
        size: const Size(500, 1600),
      );

      // Locate by controller text: scrolling disposes off-screen fields, so
      // positional finders are unreliable once the list has moved.
      final descField = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == longDescription,
      );
      expect(tester.widget<TextField>(descField).maxLines, isNull);
      expect(tester.widget<TextField>(descField).minLines, 3);
      expect(find.text('Read more'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('read-only short description also grows with the content', (tester) async {
      final container = memberContainer();
      addTearDown(container.dispose);
      await pumpModal(tester, task: adminTicket, container: container);

      final descField = find.byType(TextField).at(1);
      expect(tester.widget<TextField>(descField).maxLines, isNull);
      expect(tester.widget<TextField>(descField).minLines, 3);
      expect(find.text('Read more'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('editable description grows with the content', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpModal(
        tester,
        task: adminTicket.copyWith(description: longDescription),
        container: container,
      );

      final descField = find.byType(TextField).at(1);
      expect(tester.widget<TextField>(descField).maxLines, isNull);
      expect(tester.widget<TextField>(descField).minLines, 3);
      expect(find.text('Read more'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('attachment upload feedback', () {
    testWidgets('shows a snackbar instead of failing silently when storage is unavailable', (tester) async {
      await pumpModal(tester);

      // The attachments row sits below the fold in the modal's scroll view.
      await tester.dragUntilVisible(
        find.text('Upload File'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.tap(find.text('Upload File'));
      await tester.pumpAndSettle();

      expect(
        find.text('Attachments require a connected Supabase project.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('picker failures surface a snackbar instead of failing silently', (tester) async {
      // Make the storage service look connected so the flow reaches the
      // picker; in the test environment FilePicker has no platform
      // implementation and throws. runAsync is required because
      // Supabase.initialize touches real I/O (session recovery).
      await tester.runAsync(() => SupabaseService.instance.initialize(
            url: 'http://localhost:54321',
            anonKey: 'fake-anon-key',
          ));
      addTearDown(SupabaseService.instance.reset);

      await pumpModal(tester);

      await tester.dragUntilVisible(
        find.text('Upload File'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.tap(find.text('Upload File'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not open the file picker'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ticket comments', () {
    // The comments section sits below the fold inside the modal's scroll
    // view; drag it into view first (off-screen list children are not built).
    Future<void> revealComments(WidgetTester tester) async {
      await tester.dragUntilVisible(
        find.text('Comments'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('members can add and delete their own comments', (tester) async {
      final container = memberContainer();
      addTearDown(container.dispose);
      await pumpModal(tester, task: adminTicket, container: container);
      await revealComments(tester);

      expect(find.text('No comments yet. Start the discussion!'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      final commentField = find.ancestor(
        of: find.text('Add a comment...'),
        matching: find.byType(TextField),
      );
      await tester.enterText(commentField, 'Adding extra info');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('Adding extra info'), findsOneWidget);
      expect(find.text('No comments yet. Start the discussion!'), findsNothing);
      // Their own comment shows the delete control.
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Adding extra info'), findsNothing);
      expect(find.text('No comments yet. Start the discussion!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('members cannot delete comments written by others', (tester) async {
      final repo = FakeTaskRepository()
        ..commentStore.add(TaskComment(
          id: 'c-admin',
          taskId: 't-admin',
          workspaceId: 'ws-demo-001',
          userId: 'demo-user-123',
          userName: 'Alex',
          body: 'Admin thought this through',
        ));
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(
              UserProfile(id: 'user-456', email: 'sarah.designer@tasksphere.app', displayName: 'Sarah'),
            ),
          ),
          taskRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);
      await pumpModal(tester, task: adminTicket, container: container);
      await revealComments(tester);

      expect(find.text('Admin thought this through'), findsOneWidget);
      // No task delete (member) and no comment delete (not their comment).
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('admins can delete any comment', (tester) async {
      final repo = FakeTaskRepository()
        ..commentStore.add(TaskComment(
          id: 'c-member',
          taskId: 't-admin',
          workspaceId: 'ws-demo-001',
          userId: 'user-456',
          userName: 'Sarah',
          body: 'Member note',
        ));
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(
              UserProfile(id: 'demo-user-123', email: 'alex.admin@tasksphere.app', displayName: 'Alex'),
            ),
          ),
          isDemoUserProvider.overrideWith((ref) => false),
          taskRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);
      await pumpModal(tester, task: adminTicket, container: container);
      await revealComments(tester);

      expect(find.text('Member note'), findsOneWidget);
      // The header task-delete icon may or may not be mounted depending on
      // how far the list scrolled; the comment's icon is the last one.
      expect(find.byIcon(Icons.delete_outline), findsAtLeastNWidgets(1));

      await tester.tap(find.byIcon(Icons.delete_outline).last);
      await tester.pumpAndSettle();

      expect(find.text('Member note'), findsNothing);
      expect(repo.deletedComments, ['c-member']);
      expect(tester.takeException(), isNull);
    });
  });
}
