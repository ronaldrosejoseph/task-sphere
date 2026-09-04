import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/models/task.dart';
import 'package:task_sphere/models/subtask.dart';

TaskItem buildTask({
  String id = 'task-1',
  String laneId = 'lane-1',
  TaskPriority priority = TaskPriority.medium,
  DateTime? dueDate,
  List<Subtask> subtasks = const [],
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return TaskItem(
    id: id,
    workspaceId: 'ws-1',
    laneId: laneId,
    title: 'Test Task',
    description: 'A task for testing',
    assigneeId: 'user-1',
    assigneeEmail: 'alex@example.com',
    assigneeName: 'Alex',
    priority: priority,
    dueDate: dueDate,
    attachmentPaths: const ['ws-1/task-1/file.pdf'],
    isArchived: false,
    subtasks: subtasks,
    createdBy: 'user-1',
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

void main() {
  group('TaskItem JSON', () {
    test('roundtrips all fields through toJson/fromJson', () {
      final task = buildTask(
        dueDate: DateTime.utc(2026, 9, 1, 12, 30),
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 10),
      );

      final restored = TaskItem.fromJson(task.toJson());

      expect(restored.id, task.id);
      expect(restored.workspaceId, task.workspaceId);
      expect(restored.laneId, task.laneId);
      expect(restored.title, task.title);
      expect(restored.description, task.description);
      expect(restored.assigneeId, task.assigneeId);
      expect(restored.assigneeEmail, task.assigneeEmail);
      expect(restored.assigneeName, task.assigneeName);
      expect(restored.priority, task.priority);
      expect(restored.dueDate, task.dueDate);
      expect(restored.attachmentPaths, task.attachmentPaths);
      expect(restored.isArchived, task.isArchived);
      expect(restored.createdBy, task.createdBy);
      expect(restored.createdAt, task.createdAt);
      expect(restored.updatedAt, task.updatedAt);
    });

    test('fromJson falls back to medium priority for unknown values', () {
      final json = buildTask().toJson()..['priority'] = 'critical';
      expect(TaskItem.fromJson(json).priority, TaskPriority.medium);
    });

    test('fromJson accepts uppercase priority names', () {
      final json = buildTask().toJson()..['priority'] = 'URGENT';
      expect(TaskItem.fromJson(json).priority, TaskPriority.urgent);
    });

    test('fromJson tolerates missing optional fields', () {
      final task = TaskItem.fromJson({
        'id': 'task-x',
        'workspace_id': 'ws-1',
        'lane_id': 'lane-1',
      });
      expect(task.title, 'Untitled Task');
      expect(task.description, '');
      expect(task.priority, TaskPriority.medium);
      expect(task.dueDate, isNull);
      expect(task.attachmentPaths, isEmpty);
      expect(task.isArchived, false);
      expect(task.subtasks, isEmpty);
    });
  });

  group('TaskItem subtasksProgress', () {
    test('is 0.0 when there are no subtasks', () {
      expect(buildTask().subtasksProgress, 0.0);
    });

    test('computes completed ratio', () {
      final task = buildTask(subtasks: [
        Subtask(id: 's1', taskId: 'task-1', title: 'a', isCompleted: true),
        Subtask(id: 's2', taskId: 'task-1', title: 'b', isCompleted: false),
        Subtask(id: 's3', taskId: 'task-1', title: 'c', isCompleted: true),
      ]);
      expect(task.subtasksProgress, closeTo(2 / 3, 0.0001));
    });

    test('is 1.0 when all subtasks are completed', () {
      final task = buildTask(subtasks: [
        Subtask(id: 's1', taskId: 'task-1', title: 'a', isCompleted: true),
      ]);
      expect(task.subtasksProgress, 1.0);
    });
  });

  group('TaskItem copyWith', () {
    test('keeps identity fields and overrides the requested ones', () {
      final original = buildTask(
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 10),
      );

      final copied = original.copyWith(laneId: 'lane-2', title: 'Renamed');

      expect(copied.id, original.id);
      expect(copied.workspaceId, original.workspaceId);
      expect(copied.laneId, 'lane-2');
      expect(copied.title, 'Renamed');
      expect(copied.description, original.description);
      expect(copied.priority, original.priority);
      expect(copied.createdAt, original.createdAt);
    });

    test('bumps updatedAt to now', () {
      final original = buildTask(updatedAt: DateTime.utc(2020, 1, 1));
      final copied = original.copyWith(title: 'Changed');
      expect(copied.updatedAt.isAfter(original.updatedAt), isTrue);
    });

    test('omitted assignee parameters keep the current values', () {
      final original = buildTask();
      final copied = original.copyWith(laneId: 'lane-2');

      expect(copied.assigneeId, 'user-1');
      expect(copied.assigneeEmail, 'alex@example.com');
      expect(copied.assigneeName, 'Alex');
    });

    test('an explicit null assignee clears the assignment', () {
      final original = buildTask();
      final copied = original.copyWith(
        assigneeId: null,
        assigneeEmail: null,
        assigneeName: null,
      );

      expect(copied.assigneeId, isNull);
      expect(copied.assigneeEmail, isNull);
      expect(copied.assigneeName, isNull);
    });

    test('a non-null assignee replaces the current one', () {
      final original = buildTask();
      final copied = original.copyWith(assigneeEmail: 'bob@example.com');

      expect(copied.assigneeEmail, 'bob@example.com');
      expect(copied.assigneeId, original.assigneeId);
    });
  });

  group('TaskPriorityExtension', () {
    test('maps every priority to a label', () {
      for (final priority in TaskPriority.values) {
        expect(priority.label, isNotEmpty);
      }
    });

    test('labels match expected values', () {
      expect(TaskPriority.urgent.label, 'Urgent');
      expect(TaskPriority.high.label, 'High');
      expect(TaskPriority.medium.label, 'Medium');
      expect(TaskPriority.low.label, 'Low');
    });
  });

  group('compareTasksForBoard', () {
    test('orders by priority urgency first', () {
      final urgent = buildTask(id: 'u', priority: TaskPriority.urgent);
      final low = buildTask(id: 'l', priority: TaskPriority.low);
      expect(compareTasksForBoard(urgent, low), lessThan(0));
      expect(compareTasksForBoard(low, urgent), greaterThan(0));
      expect(compareTasksForBoard(urgent, urgent), 0);
    });

    test('breaks priority ties by soonest due date', () {
      final later = buildTask(
        id: 'later',
        priority: TaskPriority.high,
        dueDate: DateTime.utc(2026, 9, 10),
      );
      final sooner = buildTask(
        id: 'sooner',
        priority: TaskPriority.high,
        dueDate: DateTime.utc(2026, 9, 1),
      );
      expect(compareTasksForBoard(sooner, later), lessThan(0));
    });

    test('places tasks without due date after dated ones', () {
      final noDue = buildTask(id: 'nodue', priority: TaskPriority.low);
      final due = buildTask(
        id: 'due',
        priority: TaskPriority.low,
        dueDate: DateTime.utc(2026, 9, 1),
      );
      expect(compareTasksForBoard(due, noDue), lessThan(0));
      expect(compareTasksForBoard(noDue, noDue), 0);
    });
  });
}
