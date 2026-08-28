import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/subtask.dart';
import '../../models/task.dart';
import '../services/supabase_service.dart';

/// Persistence boundary for tasks and subtasks.
///
/// `fetchTasks` returns `null` when the repository holds no persisted
/// state (offline mode), in which case callers keep their in-memory data.
abstract class TaskRepository {
  bool get isPersistent;

  Future<List<TaskItem>?> fetchTasks(String workspaceId);

  Future<void> insertTask(TaskItem task);

  Future<void> updateTask(TaskItem task);

  Future<void> deleteTask(String taskId);

  Stream<void> watchTasks(String workspaceId);
}

class InMemoryTaskRepository implements TaskRepository {
  @override
  bool get isPersistent => false;

  @override
  Future<List<TaskItem>?> fetchTasks(String workspaceId) async => null;

  @override
  Future<void> insertTask(TaskItem task) async {}

  @override
  Future<void> updateTask(TaskItem task) async {}

  @override
  Future<void> deleteTask(String taskId) async {}

  @override
  Stream<void> watchTasks(String workspaceId) => const Stream.empty();
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
  Future<void> updateTask(TaskItem task) async {
    try {
      await _client.from('tasks').update(task.toJson()).eq('id', task.id);
      await _client.from('subtasks').delete().eq('task_id', task.id);
      if (task.subtasks.isNotEmpty) {
        await _insertSubtasks(task.id, task.subtasks);
      }
    } catch (e) {
      debugPrint('Task update error: $e');
    }
  }

  @override
  Future<void> deleteTask(String taskId) async {
    try {
      await _client.from('tasks').delete().eq('id', taskId);
    } catch (e) {
      debugPrint('Task delete error: $e');
    }
  }

  Future<void> _insertSubtasks(String taskId, List<Subtask> subtasks) async {
    await _client.from('subtasks').insert([
      for (final subtask in subtasks) subtask.toJson(),
    ]);
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
}

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final client = SupabaseService.instance.client;
  if (client != null) return SupabaseTaskRepository(client);
  return InMemoryTaskRepository();
});
