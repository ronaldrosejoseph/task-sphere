import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/core/repositories/workspace_repository.dart';
import 'package:task_sphere/models/lane.dart';
import 'package:task_sphere/models/task.dart';
import 'package:task_sphere/models/workspace.dart';
import 'package:task_sphere/providers/task_provider.dart';
import 'package:task_sphere/providers/workspace_provider.dart';

class _CustomWorkspaceNotifier extends WorkspaceNotifier {
  _CustomWorkspaceNotifier(WorkspaceState initialState)
      : super(InMemoryWorkspaceRepository()) {
    state = initialState;
  }
}

ProviderContainer makeContainer({WorkspaceState? workspaceState}) {
  final container = ProviderContainer(
    overrides: workspaceState == null
        ? []
        : [
            activeWorkspaceProvider.overrideWith(
              (ref) => _CustomWorkspaceNotifier(workspaceState),
            ),
          ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('TaskNotifier', () {
    test('seeds demo tasks for the default workspace', () {
      final tasks = makeContainer().read(tasksProvider);
      expect(tasks.length, 5);
      expect(tasks.map((t) => t.workspaceId).toSet(), {'ws-demo-001'});
    });

    test('does not seed when workspace has fewer than 5 lanes', () {
      final ws = Workspace(id: 'ws-small', name: 'Small', adminId: 'admin');
      final state = WorkspaceState(
        activeWorkspace: ws,
        allWorkspaces: [ws],
        lanes: [
          KanbanLane(id: 'lane-a', workspaceId: 'ws-small', title: 'To Do'),
        ],
      );
      final tasks = makeContainer(workspaceState: state).read(tasksProvider);
      expect(tasks, isEmpty);
    });

    test('moveTaskLane updates the lane of the matching task only', () {
      final container = makeContainer();
      final notifier = container.read(tasksProvider.notifier);
      final before = container.read(tasksProvider);

      notifier.moveTaskLane('task-101', 'lane-4');

      final after = container.read(tasksProvider);
      expect(
        after.firstWhere((t) => t.id == 'task-101').laneId,
        'lane-4',
      );
      for (final task in after.where((t) => t.id != 'task-101')) {
        expect(
          task.laneId,
          before.firstWhere((t) => t.id == task.id).laneId,
        );
      }
    });

    test('addTask prepends the new task and keeps existing ones', () {
      final container = makeContainer();
      final notifier = container.read(tasksProvider.notifier);
      final newTask = TaskItem(
        id: 'task-new',
        workspaceId: 'ws-demo-001',
        laneId: 'lane-1',
        title: 'Brand new task',
      );

      notifier.addTask(newTask);

      final tasks = container.read(tasksProvider);
      expect(tasks.first.id, 'task-new');
      expect(tasks.length, 6);
    });

    test('updateTask replaces the matching task', () {
      final container = makeContainer();
      final notifier = container.read(tasksProvider.notifier);
      final original = container.read(tasksProvider).first;

      final updated = original.copyWith(title: 'Updated title');
      notifier.updateTask(updated);

      final tasks = container.read(tasksProvider);
      expect(tasks.firstWhere((t) => t.id == original.id).title, 'Updated title');
      expect(tasks.length, 5);
    });

    test('deleteTask removes the matching task', () {
      final container = makeContainer();
      final notifier = container.read(tasksProvider.notifier);

      notifier.deleteTask('task-101');

      final tasks = container.read(tasksProvider);
      expect(tasks.any((t) => t.id == 'task-101'), isFalse);
      expect(tasks.length, 4);
    });

    test('toggleSubtask flips completion of the matching subtask', () {
      final container = makeContainer();
      final notifier = container.read(tasksProvider.notifier);
      final before = container
          .read(tasksProvider)
          .firstWhere((t) => t.id == 'task-101')
          .subtasks
          .first
          .isCompleted;

      notifier.toggleSubtask('task-101', 'st-1');

      final subtask = container
          .read(tasksProvider)
          .firstWhere((t) => t.id == 'task-101')
          .subtasks
          .firstWhere((s) => s.id == 'st-1');
      expect(subtask.isCompleted, !before);
    });

    test('addLoggedTime accumulates seconds on the matching task', () {
      final container = makeContainer();
      final notifier = container.read(tasksProvider.notifier);
      final before = container
          .read(tasksProvider)
          .firstWhere((t) => t.id == 'task-102')
          .loggedSeconds;

      notifier.addLoggedTime('task-102', 900);

      final after = container
          .read(tasksProvider)
          .firstWhere((t) => t.id == 'task-102')
          .loggedSeconds;
      expect(after, before + 900);
    });

    test('addAttachmentPath appends to the matching task', () {
      final container = makeContainer();
      final notifier = container.read(tasksProvider.notifier);

      notifier.addAttachmentPath('task-103', 'ws-1/task-103/file.png');

      final task = container.read(tasksProvider).firstWhere((t) => t.id == 'task-103');
      expect(task.attachmentPaths, contains('ws-1/task-103/file.png'));
    });

    test('archiveTask toggles the archived flag', () {
      final container = makeContainer();
      final notifier = container.read(tasksProvider.notifier);

      notifier.archiveTask('task-101', true);

      expect(
        container.read(tasksProvider).firstWhere((t) => t.id == 'task-101').isArchived,
        isTrue,
      );

      notifier.archiveTask('task-101', false);

      expect(
        container.read(tasksProvider).firstWhere((t) => t.id == 'task-101').isArchived,
        isFalse,
      );
    });
  });

  group('ActivityLogNotifier', () {
    test('addLog prepends new entries with generated ids', () {
      final container = makeContainer();
      final notifier = container.read(activityLogsProvider.notifier);

      notifier.addLog('ws-1', 'Alex', 'Created task "A"', taskId: 'task-1');
      notifier.addLog('ws-1', 'Alex', 'Created task "B"');

      final logs = container.read(activityLogsProvider);
      expect(logs.length, 2);
      expect(logs.first.action, 'Created task "B"');
      expect(logs.last.action, 'Created task "A"');
      expect(logs.first.id, isNotEmpty);
      expect(logs.first.taskId, isNull);
      expect(logs.last.taskId, 'task-1');
    });

    test('starts empty', () {
      expect(makeContainer().read(activityLogsProvider), isEmpty);
    });
  });

  group('Task filter providers', () {
    test('default filter state', () {
      final container = makeContainer();
      expect(container.read(taskFilterSearchProvider), '');
      expect(container.read(taskFilterPriorityProvider), isNull);
      expect(container.read(taskFilterAssigneeProvider), isNull);
      expect(container.read(showArchivedTasksProvider), isFalse);
    });

    test('filter values can be set', () {
      final container = makeContainer();
      container.read(taskFilterSearchProvider.notifier).state = 'design';
      container.read(taskFilterPriorityProvider.notifier).state = TaskPriority.urgent;
      container.read(taskFilterAssigneeProvider.notifier).state = 'alex@example.com';
      container.read(showArchivedTasksProvider.notifier).state = true;

      expect(container.read(taskFilterSearchProvider), 'design');
      expect(container.read(taskFilterPriorityProvider), TaskPriority.urgent);
      expect(container.read(taskFilterAssigneeProvider), 'alex@example.com');
      expect(container.read(showArchivedTasksProvider), isTrue);
    });
  });
}
