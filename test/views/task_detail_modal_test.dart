import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/core/repositories/activity_log_repository.dart';
import 'package:task_sphere/core/repositories/task_repository.dart';
import 'package:task_sphere/core/services/supabase_service.dart';
import 'package:task_sphere/models/task.dart';
import 'package:task_sphere/models/subtask.dart';
import 'package:task_sphere/models/task_comment.dart';
import 'package:task_sphere/models/activity_log.dart';
import 'package:task_sphere/models/user_profile.dart';
import 'package:task_sphere/providers/auth_provider.dart';
import 'package:task_sphere/providers/task_provider.dart';
import 'package:task_sphere/views/task_detail/task_detail_modal.dart';
import '../providers/repository_provider_test.dart'
    show FakeActivityLogRepository, FakeTaskRepository;

/// Delays the task INSERT until the test releases it, simulating a slow
/// database round trip.
class _GatedTaskRepository extends FakeTaskRepository {
  _GatedTaskRepository(this.gate);

  final Completer<void> gate;

  @override
  Future<void> insertTask(TaskItem task) async {
    await gate.future;
    await super.insertTask(task);
  }
}

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this.user);

  final UserProfile? user;

  @override
  UserProfile? build() => user;
}

class _FixedActivityLogNotifier extends ActivityLogNotifier {
  _FixedActivityLogNotifier(this.logs);

  final List<ActivityLog> logs;

  @override
  List<ActivityLog> build() => logs;
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
    // The tracker sits below the metadata section; scroll it into view on
    // the phone-sized viewport, then assert it renders without overflow.
    await tester.dragUntilVisible(
      find.text('Time Tracker'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
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

  testWidgets('the activity log waits for the task insert before saving', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final gate = Completer<void>();
    final taskRepo = _GatedTaskRepository(gate);
    final logRepo = FakeActivityLogRepository();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'user-abc', email: 'alex@x.com', displayName: 'Alex'),
          ),
        ),
        isDemoUserProvider.overrideWith((ref) => false),
        taskRepositoryProvider.overrideWith((ref) => taskRepo),
        activityLogRepositoryProvider.overrideWith((ref) => logRepo),
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

    await tester.enterText(find.byType(TextField).first, 'Sequenced ticket');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Task'));
    await tester.pump();

    // The task INSERT is still in flight: the modal must stay open and no
    // activity log (whose task_id references the tasks row) may be written.
    expect(find.byType(TaskDetailModal), findsOneWidget);
    expect(logRepo.inserted, isEmpty);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(TaskDetailModal), findsNothing);
    expect(taskRepo.inserted.single.title, 'Sequenced ticket');
    final log = logRepo.inserted.single;
    expect(log.action, 'Created task "Sequenced ticket"');
    expect(log.taskId, taskRepo.inserted.single.id);
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

  group('created date display', () {
    final datedTicket = TaskItem(
      id: 't-dated',
      workspaceId: 'ws-demo-001',
      laneId: 'lane-1',
      title: 'Dated ticket',
      createdAt: DateTime(2025, 3, 14),
    );

    testWidgets('edit mode shows the created date', (tester) async {
      await pumpModal(tester, task: datedTicket, size: const Size(900, 1400));

      expect(find.text('Created'), findsOneWidget);
      expect(find.text('Mar 14, 2025'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('create mode hides the created field', (tester) async {
      await pumpModal(tester, size: const Size(900, 1400));

      expect(find.text('Created'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('created and due dates share one container', (tester) async {
      await pumpModal(tester, task: datedTicket, size: const Size(900, 1400));

      final datesBox = find
          .ancestor(
            of: find.text('Created'),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.padding != null &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).border is Border,
            ),
          )
          .first;
      expect(datesBox, findsOneWidget);
      expect(
        find.descendant(of: datesBox, matching: find.text('Due Date')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('metadata field layout', () {
    testWidgets('on a phone the metadata fields stretch full width', (tester) async {
      await pumpModal(tester, size: const Size(360, 1400));

      final dropdowns = find.byWidgetPredicate((w) => w is FormField);
      expect(dropdowns, findsNWidgets(3));
      for (final element in dropdowns.evaluate()) {
        // The modal content is ~280px wide on a 360px phone; fixed 160-220px
        // fields used to leave ragged gaps.
        expect(tester.getSize(find.byWidget(element.widget)).width, greaterThan(250));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet widths also stack the fields instead of one cramped row', (tester) async {
      await pumpModal(tester, size: const Size(800, 1400));

      final dropdowns = find.byWidgetPredicate((w) => w is FormField);
      expect(dropdowns, findsNWidgets(3));
      for (final element in dropdowns.evaluate()) {
        // Regression: at tablet widths the 200/160/220px dropdowns used to
        // share a row with the dates container; each field now spans the
        // full ~650px modal content.
        expect(tester.getSize(find.byWidget(element.widget)).width, greaterThan(300));
      }
      // The dates container sits on its own full-width row below the fields.
      final datesBox = find.ancestor(
        of: find.text('Due Date'),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.padding != null &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).border is Border,
        ),
      );
      expect(datesBox, findsOneWidget);
      expect(tester.getSize(datesBox).width, greaterThan(300));
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

  group('upload file type verification', () {
    test('allows common image extensions regardless of case', () {
      for (final name in [
        'photo.jpg',
        'PHOTO.JPEG',
        'a.png',
        'b.gif',
        'c.webp',
        'd.heic',
        'e.heif',
        'f.bmp',
        'Screenshot 2026-08-31 at 12.01.26 AM.png',
      ]) {
        expect(TaskDetailModal.isAllowedImageFileName(name), isTrue, reason: name);
      }
    });

    test('rejects non-image files and extensionless names', () {
      for (final name in [
        'doc.pdf',
        'notes.txt',
        'clip.mp4',
        'archive.zip',
        'script.js',
        'image.png.exe',
        'noext',
      ]) {
        expect(TaskDetailModal.isAllowedImageFileName(name), isFalse, reason: name);
      }
    });
  });

  group('task deletion', () {
    // Pushed on a real dialog route so the confirm flow can pop the modal.
    Future<void> pumpDeletableModal(WidgetTester tester, ProviderContainer container) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

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
                      builder: (_) => TaskDetailModal(task: adminTicket),
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

      // The modal never watches tasksProvider (it only uses its notifier), so
      // the repo fetch only starts once the provider is first read.
      container.read(tasksProvider);
      await tester.pumpAndSettle();
    }

    ProviderContainer deleteContainer(FakeTaskRepository repo) {
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
      return container;
    }

    testWidgets('tapping delete asks for confirmation and Cancel keeps the task', (tester) async {
      final repo = FakeTaskRepository()..stored.add(adminTicket);
      final container = deleteContainer(repo);
      await pumpDeletableModal(tester, container);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Delete this task?'), findsOneWidget);
      expect(
        find.textContaining('deletes the task along with its comments'),
        findsOneWidget,
      );

      // Scoped to the dialog: the modal's own bottom row also has a Cancel.
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Delete this task?'), findsNothing);
      expect(container.read(tasksProvider).any((t) => t.id == 't-admin'), isTrue);
      expect(repo.deleted, isEmpty);
      expect(find.byType(TaskDetailModal), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirming the dialog deletes the task and closes the modal', (tester) async {
      final repo = FakeTaskRepository()..stored.add(adminTicket);
      final container = deleteContainer(repo);
      await pumpDeletableModal(tester, container);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(container.read(tasksProvider).any((t) => t.id == 't-admin'), isFalse);
      expect(repo.deleted, ['t-admin']);
      expect(find.byType(TaskDetailModal), findsNothing);
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
          displayName: 'Alex',
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
          displayName: 'Sarah',
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

  group('ticket activity feed', () {
    testWidgets('shows only this ticket entries at the bottom of the modal', (tester) async {
      final container = ProviderContainer(
        overrides: [
          activityLogsProvider.overrideWith(
            () => _FixedActivityLogNotifier([
              ActivityLog(
                id: 'log-1',
                taskId: 't-admin',
                workspaceId: 'ws-demo-001',
                displayName: 'Alex Morgan',
                action: 'Moved from To Do to In Progress',
              ),
              ActivityLog(
                id: 'log-2',
                taskId: 't-other',
                workspaceId: 'ws-demo-001',
                displayName: 'Sarah Designer',
                action: 'Created task "Other"',
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await pumpModal(
        tester,
        task: adminTicket,
        container: container,
        size: const Size(500, 1400),
      );

      // The feed is the last section; scroll it into view.
      await tester.dragUntilVisible(
        find.text('Activity'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Moved from To Do to In Progress'), findsOneWidget);
      expect(find.text('Alex Morgan'), findsOneWidget);
      // Entries for other tickets are filtered out.
      expect(find.text('Created task "Other"'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('attachments sit above comments, the activity feed last', (tester) async {
      final container = memberContainer();
      addTearDown(container.dispose);
      await pumpModal(
        tester,
        task: adminTicket,
        container: container,
        size: const Size(900, 1400),
      );

      // Scroll to the very bottom: the feed is the last section.
      await tester.dragUntilVisible(
        find.text('Activity'),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      final attachmentsY = tester.getTopLeft(find.text('Attachments')).dy;
      final commentsY = tester.getTopLeft(find.text('Comments')).dy;
      final activityY = tester.getTopLeft(find.text('Activity')).dy;
      expect(attachmentsY, lessThan(commentsY));
      expect(commentsY, lessThan(activityY));
      expect(tester.takeException(), isNull);
    });

    testWidgets('saving a checked subtask logs it on the feed with the display name', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Default providers sign in the demo user (display name 'Alex Morgan').
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final task = TaskItem(
        id: 'task-sub',
        workspaceId: 'ws-demo-001',
        laneId: 'lane-1',
        title: 'Subtask ticket',
        subtasks: [
          Subtask(
            id: 's-1',
            taskId: 'task-sub',
            title: 'First subtask',
            isCompleted: false,
          ),
        ],
      );

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
                      builder: (_) => TaskDetailModal(task: task),
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

      await tester.dragUntilVisible(
        find.text('Subtasks Checklist'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Task'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskDetailModal), findsNothing);
      final taskLogs = container
          .read(activityLogsProvider)
          .where((l) => l.taskId == 'task-sub')
          .toList();
      expect(
        taskLogs.map((l) => l.action),
        contains('Checked subtask "First subtask"'),
      );
      // The demo actor resolves to the member display name, never the email
      // prefix or the raw account name.
      final check = taskLogs.firstWhere((l) => l.action.startsWith('Checked'));
      expect(check.displayName, 'Alex Morgan');
      expect(tester.takeException(), isNull);
    });

    testWidgets('saving without changes logs nothing on the feed', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final task = TaskItem(
        id: 'task-noop',
        workspaceId: 'ws-demo-001',
        laneId: 'lane-1',
        title: 'Noop ticket',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );

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
                      builder: (_) => TaskDetailModal(task: task),
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

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Task'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskDetailModal), findsNothing);
      expect(container.read(activityLogsProvider), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('changing priority and assignee logs granular entries', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final task = TaskItem(
        id: 'task-pa',
        workspaceId: 'ws-demo-001',
        laneId: 'lane-1',
        title: 'Priority ticket',
        priority: TaskPriority.urgent,
        assigneeEmail: 'sarah.designer@tasksphere.app',
        assigneeName: 'Sarah Designer',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );

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
                      builder: (_) => TaskDetailModal(task: task),
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

      // Priority: Urgent -> Low.
      await tester.dragUntilVisible(
        find.text('Urgent'),
        find.byType(Scrollable).first,
        const Offset(0, -150),
      );
      await tester.tap(find.text('Urgent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Low').last);
      await tester.pumpAndSettle();

      // Assignee: Sarah Designer -> Alex Morgan.
      await tester.dragUntilVisible(
        find.text('Sarah Designer'),
        find.byType(Scrollable).first,
        const Offset(0, -150),
      );
      await tester.tap(find.text('Sarah Designer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex Morgan').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Task'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskDetailModal), findsNothing);
      final actions = container
          .read(activityLogsProvider)
          .where((l) => l.taskId == 'task-pa')
          .map((l) => l.action)
          .toList();
      expect(actions, contains('Changed priority from Urgent to Low'));
      expect(
        actions,
        contains('Changed assignee from Sarah Designer to Alex Morgan'),
      );
      // No generic entry: every change is represented specifically.
      expect(actions.any((a) => a.startsWith('Updated task')), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('choosing Unassigned clears the assignee and logs it', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      // task-101 is seeded with Sarah Designer as its assignee.
      final task =
          container.read(tasksProvider).firstWhere((t) => t.id == 'task-101');
      expect(task.assigneeEmail, 'sarah.designer@tasksphere.app');

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
                      builder: (_) => TaskDetailModal(task: task),
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

      await tester.dragUntilVisible(
        find.text('Sarah Designer'),
        find.byType(Scrollable).first,
        const Offset(0, -150),
      );
      await tester.tap(find.text('Sarah Designer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unassigned').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Task'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskDetailModal), findsNothing);
      final saved =
          container.read(tasksProvider).firstWhere((t) => t.id == 'task-101');
      expect(saved.assigneeEmail, isNull);
      expect(saved.assigneeName, isNull);
      final actions = container
          .read(activityLogsProvider)
          .where((l) => l.taskId == 'task-101')
          .map((l) => l.action)
          .toList();
      expect(
        actions,
        contains('Changed assignee from Sarah Designer to Unassigned'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('description, due date, and subtask edits log granular entries', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final task = TaskItem(
        id: 'task-gran',
        workspaceId: 'ws-demo-001',
        laneId: 'lane-1',
        title: 'Granular ticket',
        description: 'Old description',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        subtasks: [
          Subtask(
            id: 's-keep',
            taskId: 'task-gran',
            title: 'Keep me',
            isCompleted: false,
          ),
        ],
      );

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
                      builder: (_) => TaskDetailModal(task: task),
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

      // Description: replace the content.
      final descField = find.ancestor(
        of: find.text('Add details, context, or requirements...'),
        matching: find.byType(TextField),
      );
      await tester.enterText(descField, 'New description');
      await tester.pumpAndSettle();

      // Due date: none -> today (picked via the date picker).
      await tester.dragUntilVisible(
        find.text('Set Due Date'),
        find.byType(Scrollable).first,
        const Offset(0, -150),
      );
      await tester.tap(find.text('Set Due Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Subtasks: add one, remove the original.
      await tester.dragUntilVisible(
        find.text('Add a subtask item...'),
        find.byType(Scrollable).first,
        const Offset(0, -150),
      );
      final subtaskField = find.ancestor(
        of: find.text('Add a subtask item...'),
        matching: find.byType(TextField),
      );
      await tester.enterText(subtaskField, 'Extra item');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Keep me'),
        find.byType(Scrollable).first,
        const Offset(0, -150),
      );
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Keep me'),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Task'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskDetailModal), findsNothing);
      final actions = container
          .read(activityLogsProvider)
          .where((l) => l.taskId == 'task-gran')
          .map((l) => l.action)
          .toList();
      expect(actions, contains('Changed description'));
      expect(
        actions,
        contains(
          'Changed due date from None to '
          '${DateFormat('MMM dd, yyyy').format(DateTime.now())}',
        ),
      );
      expect(actions, contains('Added subtask "Extra item"'));
      expect(actions, contains('Removed subtask "Keep me"'));
      // No generic entry: every change is represented specifically.
      expect(actions.any((a) => a.startsWith('Updated task')), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new subtask checked before saving logs both entries', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final task = TaskItem(
        id: 'task-newchk',
        workspaceId: 'ws-demo-001',
        laneId: 'lane-1',
        title: 'New checked subtask ticket',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );

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
                      builder: (_) => TaskDetailModal(task: task),
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

      // Add a subtask and tick it before saving.
      await tester.dragUntilVisible(
        find.text('Add a subtask item...'),
        find.byType(Scrollable).first,
        const Offset(0, -150),
      );
      final subtaskField = find.ancestor(
        of: find.text('Add a subtask item...'),
        matching: find.byType(TextField),
      );
      await tester.enterText(subtaskField, 'Fresh item');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Task'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskDetailModal), findsNothing);
      final actions = container
          .read(activityLogsProvider)
          .where((l) => l.taskId == 'task-newchk')
          .map((l) => l.action)
          .toList();
      // Regression: a brand-new checked subtask only logged the add; the
      // check (who ticked it) was lost.
      expect(actions, contains('Added subtask "Fresh item"'));
      expect(actions, contains('Checked subtask "Fresh item"'));
      expect(tester.takeException(), isNull);
    });
  });

  group('time tracker', () {
    testWidgets('a running timer survives closing and reopening the modal', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final task = TaskItem(
        id: 'task-timer',
        workspaceId: 'ws-demo-001',
        laneId: 'lane-1',
        title: 'Timed ticket',
      );

      await pumpModal(
        tester,
        task: task,
        container: container,
        size: const Size(900, 1400),
      );
      expect(find.widgetWithText(ElevatedButton, 'Start Timer'), findsOneWidget);

      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Start Timer'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Start Timer'));
      // The running session starts a periodic ticker, so pump fixed frames
      // rather than pumpAndSettle.
      await tester.pump();
      expect(find.widgetWithText(ElevatedButton, 'Pause'), findsOneWidget);
      // Regression: the button used to duplicate the session time next to
      // the label while "Total Logged" showed it again below.
      expect(find.textContaining('Pause ('), findsNothing);

      // Reopen the ticket: the session still runs, so the button shows Pause.
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
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.widgetWithText(ElevatedButton, 'Pause'), findsOneWidget);
      expect(container.read(runningTimersProvider).containsKey('task-timer'), isTrue);

      // Stop the timer so the periodic ticker is cancelled before teardown.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Pause'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ElevatedButton, 'Start Timer'), findsOneWidget);
      expect(container.read(runningTimersProvider), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
