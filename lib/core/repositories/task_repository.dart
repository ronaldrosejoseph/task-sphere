import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/subtask.dart';
import '../../models/task.dart';
import '../../models/task_comment.dart';
import '../../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';

/// Persistence boundary for tasks and subtasks.
///
/// `fetchTasks` returns `null` when the repository holds no persisted
/// state (offline mode), in which case callers keep their in-memory data.
abstract class TaskRepository {
  bool get isPersistent;

  Future<List<TaskItem>?> fetchTasks(String workspaceId);

  Future<void> insertTask(TaskItem task);

  /// Saves the row only when no other device changed it since [task]'s
  /// `updated_at` version was read. Returns the saved row — with the
  /// server-stamped version — or null when another write landed first
  /// (callers surface the conflict instead of silently overwriting).
  /// Transport errors are rethrown so they are not mistaken for conflicts.
  Future<TaskItem?> updateTask(TaskItem task);

  Future<void> deleteTask(String taskId);

  Future<List<TaskComment>?> fetchComments(String taskId);

  Future<void> insertComment(TaskComment comment);

  Future<void> deleteComment(String commentId);

  Stream<void> watchTasks(String workspaceId);

  Stream<void> watchComments(String taskId);
}

class InMemoryTaskRepository implements TaskRepository {
  @override
  bool get isPersistent => false;

  @override
  Future<List<TaskItem>?> fetchTasks(String workspaceId) async => null;

  @override
  Future<void> insertTask(TaskItem task) async {}

  @override
  Future<TaskItem?> updateTask(TaskItem task) async => task;

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

  @override
  Stream<void> watchComments(String taskId) => const Stream.empty();
}

class SupabaseTaskRepository implements TaskRepository {
  final SupabaseClient _client;

  SupabaseTaskRepository(this._client);

  @override
  bool get isPersistent => true;

  @override
  Future<List<TaskItem>?> fetchTasks(String workspaceId) async {
    try {
      final response = await _client
          .from('tasks')
          .select()
          .eq('workspace_id', workspaceId)
          .order('created_at');
      final taskRows = (response as List)
          .map((row) => row as Map<String, dynamic>)
          .toList();
      if (taskRows.isEmpty) return [];

      final taskIds = taskRows.map((row) => row['id'] as String).toList();
      final subtaskResponse = await _client
          .from('subtasks')
          .select()
          .inFilter('task_id', taskIds)
          .order('order_index');
      final subtasksByTask = <String, List<Subtask>>{};
      for (final row in subtaskResponse as List) {
        final subtask = Subtask.fromJson(row as Map<String, dynamic>);
        subtasksByTask.putIfAbsent(subtask.taskId, () => []).add(subtask);
      }

      return taskRows
          .map((row) => TaskItem.fromJson(
                row,
                subtasks: subtasksByTask[row['id'] as String] ?? [],
              ))
          .toList();
    } catch (e) {
      debugPrint('Task fetch error: $e');
      return null;
    }
  }

  @override
  Future<void> insertTask(TaskItem task) async {
    try {
      await _client.from('tasks').insert(task.toJson());
      if (task.subtasks.isNotEmpty) {
        await _insertSubtasks(task.id, task.subtasks);
      }
    } catch (e) {
      debugPrint('Task insert error: $e');
    }
  }

  @override
  Future<TaskItem?> updateTask(TaskItem task) async {
    try {
      final response = await _client
          .from('tasks')
          .update(task.toJson())
          .eq('id', task.id)
          // The version this edit was based on; the DB trigger bumps
          // updated_at on every write, so a stale save matches no row.
          .eq('updated_at', task.updatedAt.toIso8601String())
          .select();
      final rows = response as List;
      if (rows.isEmpty) {
        debugPrint('Task update conflict: ${task.id}');
        return null;
      }
      // Subtasks are rewritten only when the row update applied, so a
      // losing edit can never delete the winning version's subtasks.
      await _client.from('subtasks').delete().eq('task_id', task.id);
      if (task.subtasks.isNotEmpty) {
        await _insertSubtasks(task.id, task.subtasks);
      }
      return TaskItem.fromJson(
        rows.first as Map<String, dynamic>,
        subtasks: task.subtasks,
      );
    } catch (e) {
      debugPrint('Task update error: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteTask(String taskId) async {
    try {
      await _deleteAttachments(taskId);
      // Comments and subtasks cascade with the row delete.
      await _client.from('tasks').delete().eq('id', taskId);
    } catch (e) {
      debugPrint('Task delete error: $e');
    }
  }

  /// Storage objects are not FK-bound to tasks, so the attached files must be
  /// removed explicitly. Best-effort: a cleanup failure must not block the
  /// row delete below.
  Future<void> _deleteAttachments(String taskId) async {
    try {
      final rows = await _client
          .from('tasks')
          .select('attachment_paths')
          .eq('id', taskId);
      if (rows.isEmpty) return;
      final paths = rows.first['attachment_paths'];
      if (paths is! List) return;
      await Future.wait(
        paths.whereType<String>().map(SupabaseStorageService.instance.deleteAttachment),
      );
    } catch (e) {
      debugPrint('Attachment cleanup error: $e');
    }
  }

  Future<void> _insertSubtasks(String taskId, List<Subtask> subtasks) async {
    await _client.from('subtasks').insert([
      for (final subtask in subtasks) subtask.toJson(),
    ]);
  }

  @override
  Future<List<TaskComment>?> fetchComments(String taskId) async {
    try {
      final response = await _client
          .from('task_comments')
          .select()
          .eq('task_id', taskId)
          .order('created_at');
      return (response as List)
          .map((row) => TaskComment.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Comment fetch error: $e');
      return null;
    }
  }

  @override
  Future<void> insertComment(TaskComment comment) async {
    try {
      await _client.from('task_comments').insert(comment.toJson());
    } catch (e) {
      debugPrint('Comment insert error: $e');
    }
  }

  @override
  Future<void> deleteComment(String commentId) async {
    try {
      await _client.from('task_comments').delete().eq('id', commentId);
    } catch (e) {
      debugPrint('Comment delete error: $e');
    }
  }

  @override
  Stream<void> watchTasks(String workspaceId) {
    final controller = StreamController<void>();
    final channel = _client
        .channel('tasks-$workspaceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'workspace_id',
            value: workspaceId,
          ),
          callback: (_) => controller.add(null),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'subtasks',
          callback: (_) => controller.add(null),
        )
        .subscribe();

    final stream = controller.stream;
    controller.onCancel = () => _client.removeChannel(channel);
    return stream;
  }

  @override
  Stream<void> watchComments(String taskId) {
    final controller = StreamController<void>();
    final channel = _client
        .channel('task-comments-$taskId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'task_id',
            value: taskId,
          ),
          callback: (_) => controller.add(null),
        )
        .subscribe();

    final stream = controller.stream;
    controller.onCancel = () => _client.removeChannel(channel);
    return stream;
  }
}

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final client = SupabaseService.instance.client;
  if (client == null) return InMemoryTaskRepository();
  // The demo sandbox user stays fully in-memory; real sign-ins use Supabase.
  if (ref.watch(isDemoUserProvider)) return InMemoryTaskRepository();
  return SupabaseTaskRepository(client);
});
