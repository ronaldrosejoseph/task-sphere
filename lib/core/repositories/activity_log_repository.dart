import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/activity_log.dart';
import '../../providers/demo_mode_provider.dart';
import '../services/supabase_service.dart';

/// Persistence boundary for workspace activity logs.
///
/// `fetchLogs` returns `null` when the repository holds no persisted
/// state (offline mode), in which case callers keep their in-memory data.
abstract class ActivityLogRepository {
  bool get isPersistent;

  Future<List<ActivityLog>?> fetchLogs(String workspaceId);

  Future<void> insertLog(ActivityLog log);

  Stream<void> watchLogs(String workspaceId);
}

class InMemoryActivityLogRepository implements ActivityLogRepository {
  @override
  bool get isPersistent => false;

  @override
  Future<List<ActivityLog>?> fetchLogs(String workspaceId) async => null;

  @override
  Future<void> insertLog(ActivityLog log) async {}

  @override
  Stream<void> watchLogs(String workspaceId) => const Stream.empty();
}

class SupabaseActivityLogRepository implements ActivityLogRepository {
  final SupabaseClient _client;

  SupabaseActivityLogRepository(this._client);

  @override
  bool get isPersistent => true;

  @override
  Future<List<ActivityLog>?> fetchLogs(String workspaceId) async {
    try {
      final response = await _client
          .from('activity_logs')
          .select()
          .eq('workspace_id', workspaceId)
          .order('created_at', ascending: false)
          .limit(50);
      return (response as List)
          .map((row) => ActivityLog.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Activity log fetch error: $e');
      return null;
    }
  }

  @override
  Future<void> insertLog(ActivityLog log) async {
    try {
      await _client.from('activity_logs').insert(log.toJson());
    } catch (e) {
      debugPrint('Activity log insert error: $e');
    }
  }

  @override
  Stream<void> watchLogs(String workspaceId) {
    final controller = StreamController<void>();
    final channel = _client
        .channel('activity-logs-$workspaceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'activity_logs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'workspace_id',
            value: workspaceId,
          ),
          callback: (_) => controller.add(null),
        )
        .subscribe();

    final stream = controller.stream;
    controller.onCancel = () => _client.removeChannel(channel);
    return stream;
  }
}

final activityLogRepositoryProvider = Provider<ActivityLogRepository>((ref) {
  if (ref.watch(demoModeProvider)) return InMemoryActivityLogRepository();
  final client = SupabaseService.instance.client;
  if (client != null) return SupabaseActivityLogRepository(client);
  return InMemoryActivityLogRepository();
});
