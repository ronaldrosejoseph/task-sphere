import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/repositories/activity_log_repository.dart';
import '../core/repositories/task_repository.dart';
import '../core/services/notification_service.dart';
import '../models/task.dart';
import '../models/subtask.dart';
import '../models/activity_log.dart';
import 'workspace_provider.dart';

const _uuid = Uuid();

final taskFilterSearchProvider = StateProvider<String>((ref) => '');
final taskFilterPriorityProvider = StateProvider<TaskPriority?>((ref) => null);
final taskFilterAssigneeProvider = StateProvider<String?>((ref) => null);
final showArchivedTasksProvider = StateProvider<bool>((ref) => false);

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});

final tasksProvider = StateNotifierProvider<TaskNotifier, List<TaskItem>>((ref) {
  final workspaceId =
      ref.watch(activeWorkspaceProvider.select((s) => s.activeWorkspace.id));
  final lanes = ref.read(activeWorkspaceProvider).lanes;
  final laneIds = lanes.map((l) => l.id).toList();
  final excludedLaneIds = lanes
      .where((l) {
        final title = l.title.toLowerCase();
        return title == 'done' || title == 'wont do';
      })
      .map((l) => l.id)
      .toList();
  final repo = ref.watch(taskRepositoryProvider);
  final notifications = ref.watch(notificationServiceProvider);
  final notifier =
      TaskNotifier(repo, workspaceId, laneIds, excludedLaneIds, notifications);
  notifier.init();
  return notifier;
});

final activityLogsProvider = StateNotifierProvider<ActivityLogNotifier, List<ActivityLog>>((ref) {
  final workspaceId =
      ref.watch(activeWorkspaceProvider.select((s) => s.activeWorkspace.id));
  final repo = ref.watch(activityLogRepositoryProvider);
  final notifier = ActivityLogNotifier(repo, workspaceId);
  notifier.init();
  return notifier;
});

class ActivityLogNotifier extends StateNotifier<List<ActivityLog>> {
  final ActivityLogRepository _repo;
  final String _workspaceId;

  StreamSubscription<void>? _logSub;
  Timer? _reloadDebounce;
  int _mutationCount = 0;

  ActivityLogNotifier(this._repo, this._workspaceId) : super([]);

  void init() {
    if (!_repo.isPersistent) return;
    unawaited(_load());
    _logSub = _repo.watchLogs(_workspaceId).listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 300), () {
        unawaited(_load());
      });
    });
  }

  Future<void> _load() async {
    final revision = _mutationCount;
    final logs = await _repo.fetchLogs(_workspaceId);
    if (logs == null || !mounted) return;
    if (_mutationCount != revision) {
      unawaited(_load());
      return;
    }
    state = logs;
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _reloadDebounce?.cancel();
    super.dispose();
  }

  void addLog(String workspaceId, String userName, String action, {String? taskId}) {
    _mutationCount += 1;
    final newLog = ActivityLog(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      taskId: taskId,
      userName: userName,
      action: action,
    );
    state = [newLog, ...state];
    if (_repo.isPersistent) {
      unawaited(_repo.insertLog(newLog));
    }
  }
}

class TaskNotifier extends StateNotifier<List<TaskItem>> {
  final TaskRepository _repo;
  final String workspaceId;
  final List<String> _excludedLaneIds;
  final NotificationService _notifications;

  StreamSubscription<void>? _taskSub;
  Timer? _reloadDebounce;
  int _mutationCount = 0;

  TaskNotifier(
    this._repo,
    this.workspaceId,
    List<String> laneIds,
    this._excludedLaneIds,
    this._notifications,
  ) : super(_repo.isPersistent ? [] : _seedTasks(workspaceId, laneIds)) {
    if (!_repo.isPersistent) {
      _rescheduleReminders(state);
    }
  }

  void init() {
    if (!_repo.isPersistent) return;
    unawaited(_load());
    _taskSub = _repo.watchTasks(workspaceId).listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 300), () {
        unawaited(_load());
      });
    });
  }

  Future<void> _load() async {
    final revision = _mutationCount;
    final tasks = await _repo.fetchTasks(workspaceId);
    if (tasks == null || !mounted) return;
    if (_mutationCount != revision) {
      // A local mutation happened while fetching; retry so optimistic
      // changes are not clobbered by a stale snapshot.
      unawaited(_load());
      return;
    }
    state = tasks;
    _rescheduleReminders(tasks);
  }

  /// Re-registers local due-date notifications so reminders survive
  /// app restarts.
  void _rescheduleReminders(List<TaskItem> tasks) {
    final now = DateTime.now();
    for (final task in tasks) {
      final due = task.dueDate;
      if (due == null || !due.isAfter(now)) continue;
      if (task.isArchived) continue;
      if (_excludedLaneIds.contains(task.laneId)) continue;
      unawaited(_notifications.scheduleTaskReminder(
        id: task.id.hashCode,
        title: 'Task Due: ${task.title}',
        body: 'Assigned to ${task.assigneeName ?? "Team"}. Priority: ${task.priority.label}',
        scheduledDate: due.subtract(const Duration(hours: 1)),
      ));
    }
  }

  @override
  void dispose() {
    _taskSub?.cancel();
    _reloadDebounce?.cancel();
    super.dispose();
  }

  static List<TaskItem> _seedTasks(String wsId, List<String> laneIds) {
    if (laneIds.length < 5) return [];

    final todoLane = laneIds[0];
    final inProgressLane = laneIds[1];
    final partiallyDoneLane = laneIds[2];
    final doneLane = laneIds[3];
    final wontDoLane = laneIds[4];

    final now = DateTime.now();

    return [
      TaskItem(
        id: 'task-101',
        workspaceId: wsId,
        laneId: inProgressLane,
        title: 'Design Dark Mode Glassmorphic UI System',
        description: 'Create harmonious color palettes, typography, and card components.',
        assigneeName: 'Sarah Designer',
        assigneeEmail: 'sarah.designer@tasksphere.app',
        priority: TaskPriority.urgent,
        dueDate: now.add(const Duration(days: 2)),
        estimatedHours: 8.5,
        loggedSeconds: 14400,
        subtasks: [
          Subtask(id: 'st-1', taskId: 'task-101', title: 'Typography setup (Inter font)', isCompleted: true),
          Subtask(id: 'st-2', taskId: 'task-101', title: 'Glassmorphism card decoration', isCompleted: true),
          Subtask(id: 'st-3', taskId: 'task-101', title: 'Priority pill color tokens', isCompleted: false),
        ],
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      TaskItem(
        id: 'task-102',
        workspaceId: wsId,
        laneId: todoLane,
        title: 'Implement Supabase Realtime WebSockets',
        description: 'Subscribe to tasks table insertions and updates across devices.',
        assigneeName: 'Alex Morgan',
        assigneeEmail: 'alex.admin@tasksphere.app',
        priority: TaskPriority.high,
        dueDate: now.add(const Duration(days: 4)),
        estimatedHours: 6.0,
        subtasks: [
          Subtask(id: 'st-4', taskId: 'task-102', title: 'SQL Schema migration', isCompleted: true),
          Subtask(id: 'st-5', taskId: 'task-102', title: 'WebSocket listener in Dart', isCompleted: false),
        ],
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      TaskItem(
        id: 'task-103',
        workspaceId: wsId,
        laneId: partiallyDoneLane,
        title: 'Supabase Storage File Attachment Integration',
        description: 'Upload task attachments to the private Supabase Storage bucket with workspace RLS policies.',
        assigneeName: 'Dev Team',
        assigneeEmail: 'dev.team@tasksphere.app',
        priority: TaskPriority.medium,
        dueDate: now.add(const Duration(days: 5)),
        estimatedHours: 12.0,
        loggedSeconds: 18000,
        subtasks: [
          Subtask(id: 'st-6', taskId: 'task-103', title: 'Google OAuth 2.0 flow', isCompleted: true),
          Subtask(id: 'st-7', taskId: 'task-103', title: 'Storage upload via file picker', isCompleted: true),
          Subtask(id: 'st-8', taskId: 'task-103', title: 'Attachment preview widget', isCompleted: false),
        ],
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      TaskItem(
        id: 'task-104',
        workspaceId: wsId,
        laneId: doneLane,
        title: 'Setup Flutter Multi-Platform Target Configuration',
        description: 'Enable Android, iOS, macOS desktop and Web targets.',
        assigneeName: 'Alex Morgan',
        assigneeEmail: 'alex.admin@tasksphere.app',
        priority: TaskPriority.low,
        dueDate: now.subtract(const Duration(days: 1)),
        estimatedHours: 4.0,
        loggedSeconds: 14400,
        subtasks: [
          Subtask(id: 'st-9', taskId: 'task-104', title: 'Pubspec dependency initialization', isCompleted: true),
        ],
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      TaskItem(
        id: 'task-105',
        workspaceId: wsId,
        laneId: wontDoLane,
        title: 'Legacy MySQL Server Backend',
        description: 'Replaced with 100% serverless client-side architecture using Supabase (database, auth, storage).',
        assigneeName: 'Alex Morgan',
        assigneeEmail: 'alex.admin@tasksphere.app',
        priority: TaskPriority.low,
        dueDate: now.subtract(const Duration(days: 10)),
        isArchived: true, // Marked archived as old wont do task
        createdAt: now.subtract(const Duration(days: 20)),
      ),
    ];
  }

  void moveTaskLane(String taskId, String newLaneId) {
    _mutationCount += 1;
    TaskItem? moved;
    state = state.map((task) {
      if (task.id == taskId) {
        moved = task.copyWith(laneId: newLaneId);
        return moved!;
      }
      return task;
    }).toList();
    if (_repo.isPersistent && moved != null) {
      unawaited(_repo.updateTask(moved!));
    }
  }

  void addTask(TaskItem task) {
    _mutationCount += 1;
    state = [task, ...state];
    if (_repo.isPersistent) {
      unawaited(_repo.insertTask(task));
    }

    // Trigger local notification if task has due date
    if (task.dueDate != null) {
      unawaited(_notifications.scheduleTaskReminder(
        id: task.id.hashCode,
        title: 'Task Due: ${task.title}',
        body: 'Assigned to ${task.assigneeName ?? "Team"}. Priority: ${task.priority.label}',
        scheduledDate: task.dueDate!.subtract(const Duration(hours: 1)),
      ));
    }
  }

  void updateTask(TaskItem updatedTask) {
    _mutationCount += 1;
    state = state.map((t) => t.id == updatedTask.id ? updatedTask : t).toList();
    if (_repo.isPersistent) {
      unawaited(_repo.updateTask(updatedTask));
    }
  }

  void deleteTask(String taskId) {
    _mutationCount += 1;
    state = state.where((t) => t.id != taskId).toList();
    if (_repo.isPersistent) {
      unawaited(_repo.deleteTask(taskId));
    }
  }

  void toggleSubtask(String taskId, String subtaskId) {
    _mutationCount += 1;
    TaskItem? updatedTask;
    state = state.map((task) {
      if (task.id == taskId) {
        final updatedSubtasks = task.subtasks.map((st) {
          if (st.id == subtaskId) {
            return st.copyWith(isCompleted: !st.isCompleted);
          }
          return st;
        }).toList();
        updatedTask = task.copyWith(subtasks: updatedSubtasks);
        return updatedTask!;
      }
      return task;
    }).toList();
    if (_repo.isPersistent && updatedTask != null) {
      unawaited(_repo.updateTask(updatedTask!));
    }
  }

  void addLoggedTime(String taskId, int additionalSeconds) {
    _mutationCount += 1;
    TaskItem? updatedTask;
    state = state.map((task) {
      if (task.id == taskId) {
        updatedTask = task.copyWith(loggedSeconds: task.loggedSeconds + additionalSeconds);
        return updatedTask!;
      }
      return task;
    }).toList();
    if (_repo.isPersistent && updatedTask != null) {
      unawaited(_repo.updateTask(updatedTask!));
    }
  }

  void addAttachmentPath(String taskId, String path) {
    _mutationCount += 1;
    TaskItem? updatedTask;
    state = state.map((task) {
      if (task.id == taskId) {
        final updatedPaths = [...task.attachmentPaths, path];
        updatedTask = task.copyWith(attachmentPaths: updatedPaths);
        return updatedTask!;
      }
      return task;
    }).toList();
    if (_repo.isPersistent && updatedTask != null) {
      unawaited(_repo.updateTask(updatedTask!));
    }
  }

  void archiveTask(String taskId, bool isArchived) {
    _mutationCount += 1;
    TaskItem? updatedTask;
    state = state.map((task) {
      if (task.id == taskId) {
        updatedTask = task.copyWith(isArchived: isArchived);
        return updatedTask!;
      }
      return task;
    }).toList();
    if (_repo.isPersistent && updatedTask != null) {
      unawaited(_repo.updateTask(updatedTask!));
    }
  }
}
