import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/core/repositories/task_repository.dart';
import 'package:task_sphere/core/services/notification_service.dart';
import 'package:task_sphere/models/lane.dart';
import 'package:task_sphere/models/task.dart';
import 'package:task_sphere/models/task_comment.dart';
import 'package:task_sphere/models/user_profile.dart';
import 'package:task_sphere/models/workspace.dart';
import 'package:task_sphere/providers/auth_provider.dart';
import 'package:task_sphere/providers/task_provider.dart';
import 'package:task_sphere/providers/workspace_provider.dart';

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this.user);

  final UserProfile? user;

  @override
  UserProfile? build() => user;
}

class FakeNotificationService extends NotificationService {
  final Map<int, String> scheduled = {};

  @override
  Future<void> scheduleTaskReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    scheduled[id] = title;
  }

  @override
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {}
}

class _FakeWorkspaceNotifier extends WorkspaceNotifier {
  _FakeWorkspaceNotifier(this.initialState);

  final WorkspaceState initialState;

  @override
  WorkspaceState build() => initialState;
}

class _PersistentTaskRepository implements TaskRepository {
  final List<TaskItem> stored;

  _PersistentTaskRepository(this.stored);

  @override
  bool get isPersistent => true;

  @override
  Future<List<TaskItem>?> fetchTasks(String workspaceId) async => List.of(stored);

  @override
  Future<void> insertTask(TaskItem task) async {}

  @override
  Future<void> updateTask(TaskItem task) async {}

  @override
  Future<void> deleteTask(String taskId) async {}

  @override
  Future<List<TaskComment>?> fetchComments(String taskId) async => null;

  @override
  Future<void> insertComment(TaskComment comment) async {}

  @override
  Future<void> deleteComment(String commentId) async {}

  @override
  Stream<void> watchTasks(String workspaceId) => const Stream.empty();
}

void main() {
  test('seeded demo tasks schedule reminders on startup', () {
    final fake = FakeNotificationService();
    final container = ProviderContainer(
      overrides: [notificationServiceProvider.overrideWith((ref) => fake)],
    );
    addTearDown(container.dispose);

    container.read(tasksProvider);

    // Future-dated tasks outside Done/Wont Do lanes get reminders.
    expect(fake.scheduled, contains('task-101'.hashCode));
    expect(fake.scheduled, contains('task-102'.hashCode));
    expect(fake.scheduled, contains('task-103'.hashCode));
    // Done-lane and archived tasks are skipped.
    expect(fake.scheduled, isNot(contains('task-104'.hashCode)));
    expect(fake.scheduled, isNot(contains('task-105'.hashCode)));
    expect(fake.scheduled['task-101'.hashCode],
        'Task Due: Design Dark Mode Glassmorphic UI System');
  });

  test('addTask schedules a reminder for future due dates', () {
    final fake = FakeNotificationService();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'u-1', email: 'u@x.com', displayName: 'U'),
          ),
        ),
        notificationServiceProvider.overrideWith((ref) => fake),
      ],
    );
    addTearDown(container.dispose);

    final task = TaskItem(
      id: 'new-task',
      workspaceId: 'ws-demo-001',
      laneId: 'lane-1',
      title: 'Ship release',
      dueDate: DateTime.now().add(const Duration(days: 1)),
    );
    container.read(tasksProvider.notifier).addTask(task);

    expect(fake.scheduled, contains('new-task'.hashCode));
  });

  test('persistent task load schedules reminders for due tasks', () async {
    final fake = FakeNotificationService();
    final workspace = Workspace(
      id: 'ws-1',
      name: 'W',
      adminId: 'a',
      autoExpiryLaneIds: ['lane-done'],
    );
    final lanes = [
      KanbanLane(id: 'lane-1', workspaceId: 'ws-1', title: 'To Do'),
      KanbanLane(id: 'lane-done', workspaceId: 'ws-1', title: 'Done'),
    ];
    final repo = _PersistentTaskRepository([
      TaskItem(
        id: 'due-task',
        workspaceId: 'ws-1',
        laneId: 'lane-1',
        title: 'Due soon',
        dueDate: DateTime.now().add(const Duration(days: 2)),
      ),
      TaskItem(
        id: 'done-task',
        workspaceId: 'ws-1',
        laneId: 'lane-done',
        title: 'Finished',
        dueDate: DateTime.now().add(const Duration(days: 2)),
      ),
    ]);

    final container = ProviderContainer(
      overrides: [
        taskRepositoryProvider.overrideWith((ref) => repo),
        notificationServiceProvider.overrideWith((ref) => fake),
        activeWorkspaceProvider.overrideWith(
          () => _FakeWorkspaceNotifier(WorkspaceState(
            activeWorkspace: workspace,
            allWorkspaces: [workspace],
            lanes: lanes,
          )),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(tasksProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(fake.scheduled, contains('due-task'.hashCode));
    expect(fake.scheduled, isNot(contains('done-task'.hashCode)));
  });

  test('reminder exclusion follows the configured auto-expiry lanes', () async {
    final fake = FakeNotificationService();
    final workspace = Workspace(
      id: 'ws-2',
      name: 'W',
      adminId: 'a',
      autoExpiryLaneIds: ['lane-finished'],
    );
    final lanes = [
      KanbanLane(id: 'lane-o', workspaceId: 'ws-2', title: 'Open'),
      // Renamed away from 'Done' — the title fallback would not match, but
      // the stored selection still excludes this lane from reminders.
      KanbanLane(id: 'lane-finished', workspaceId: 'ws-2', title: 'Finished'),
    ];
    final repo = _PersistentTaskRepository([
      TaskItem(
        id: 'open-task',
        workspaceId: 'ws-2',
        laneId: 'lane-o',
        title: 'Still open',
        dueDate: DateTime.now().add(const Duration(days: 2)),
      ),
      TaskItem(
        id: 'finished-task',
        workspaceId: 'ws-2',
        laneId: 'lane-finished',
        title: 'Done work',
        dueDate: DateTime.now().add(const Duration(days: 2)),
      ),
    ]);

    final container = ProviderContainer(
      overrides: [
        taskRepositoryProvider.overrideWith((ref) => repo),
        notificationServiceProvider.overrideWith((ref) => fake),
        activeWorkspaceProvider.overrideWith(
          () => _FakeWorkspaceNotifier(WorkspaceState(
            activeWorkspace: workspace,
            allWorkspaces: [workspace],
            lanes: lanes,
          )),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(tasksProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(fake.scheduled, contains('open-task'.hashCode));
    expect(fake.scheduled, isNot(contains('finished-task'.hashCode)));
  });
}
