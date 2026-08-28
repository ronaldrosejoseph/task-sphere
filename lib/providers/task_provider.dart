import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';
import '../models/subtask.dart';
import '../models/activity_log.dart';
import '../core/services/notification_service.dart';
import 'workspace_provider.dart';

const _uuid = Uuid();

final taskFilterSearchProvider = StateProvider<String>((ref) => '');
final taskFilterPriorityProvider = StateProvider<TaskPriority?>((ref) => null);
final taskFilterAssigneeProvider = StateProvider<String?>((ref) => null);
final showArchivedTasksProvider = StateProvider<bool>((ref) => false);

final tasksProvider = StateNotifierProvider<TaskNotifier, List<TaskItem>>((ref) {
  final workspaceState = ref.watch(activeWorkspaceProvider);
  return TaskNotifier(workspaceState.activeWorkspace.id, workspaceState.lanes.map((e) => e.id).toList());
});

final activityLogsProvider = StateNotifierProvider<ActivityLogNotifier, List<ActivityLog>>((ref) {
  return ActivityLogNotifier();
});

class ActivityLogNotifier extends StateNotifier<List<ActivityLog>> {
  ActivityLogNotifier() : super([]);

  void addLog(String workspaceId, String userName, String action, {String? taskId}) {
    final newLog = ActivityLog(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      taskId: taskId,
      userName: userName,
      action: action,
    );
    state = [newLog, ...state];
  }
}

class TaskNotifier extends StateNotifier<List<TaskItem>> {
  final String workspaceId;

  TaskNotifier(this.workspaceId, List<String> laneIds) : super(_seedTasks(workspaceId, laneIds));

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
        title: 'Google Drive File Attachment Integration',
        description: 'Upload task attachments directly to Google Drive folder using Drive API v3.',
        assigneeName: 'Dev Team',
        assigneeEmail: 'dev.team@tasksphere.app',
        priority: TaskPriority.medium,
        dueDate: now.add(const Duration(days: 5)),
        estimatedHours: 12.0,
        loggedSeconds: 18000,
        subtasks: [
          Subtask(id: 'st-6', taskId: 'task-103', title: 'Google OAuth 2.0 flow', isCompleted: true),
          Subtask(id: 'st-7', taskId: 'task-103', title: 'Drive API file upload stream', isCompleted: true),
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
        description: 'Replaced with 100% serverless client-side architecture using Supabase & Google Drive.',
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
    state = state.map((task) {
      if (task.id == taskId) {
        return task.copyWith(laneId: newLaneId);
      }
      return task;
    }).toList();
  }

  void addTask(TaskItem task) {
    state = [task, ...state];

    // Trigger local notification if task has due date
    if (task.dueDate != null) {
      NotificationService.instance.scheduleTaskReminder(
        id: task.id.hashCode,
        title: 'Task Due: ${task.title}',
        body: 'Assigned to ${task.assigneeName ?? "Team"}. Priority: ${task.priority.label}',
        scheduledDate: task.dueDate!.subtract(const Duration(hours: 1)),
      );
    }
  }

  void updateTask(TaskItem updatedTask) {
    state = state.map((t) => t.id == updatedTask.id ? updatedTask : t).toList();
  }

  void deleteTask(String taskId) {
    state = state.where((t) => t.id != taskId).toList();
  }

  void toggleSubtask(String taskId, String subtaskId) {
    state = state.map((task) {
      if (task.id == taskId) {
        final updatedSubtasks = task.subtasks.map((st) {
          if (st.id == subtaskId) {
            return st.copyWith(isCompleted: !st.isCompleted);
          }
          return st;
        }).toList();
        return task.copyWith(subtasks: updatedSubtasks);
      }
      return task;
    }).toList();
  }

  void addLoggedTime(String taskId, int additionalSeconds) {
    state = state.map((task) {
      if (task.id == taskId) {
        return task.copyWith(loggedSeconds: task.loggedSeconds + additionalSeconds);
      }
      return task;
    }).toList();
  }

  void addAttachmentUrl(String taskId, String url) {
    state = state.map((task) {
      if (task.id == taskId) {
        final updatedUrls = [...task.driveAttachmentUrls, url];
        return task.copyWith(driveAttachmentUrls: updatedUrls);
      }
      return task;
    }).toList();
  }

  void archiveTask(String taskId, bool isArchived) {
    state = state.map((task) {
      if (task.id == taskId) {
        return task.copyWith(isArchived: isArchived);
      }
      return task;
    }).toList();
  }
}
