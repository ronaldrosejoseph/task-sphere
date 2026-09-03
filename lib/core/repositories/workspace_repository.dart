import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../models/lane.dart';
import '../../models/workspace.dart';
import '../../providers/auth_provider.dart';
import '../services/supabase_service.dart';

const _uuid = Uuid();

typedef WorkspaceSnapshot = ({Workspace workspace, List<KanbanLane> lanes});
typedef WorkspacesSnapshot = ({List<Workspace> workspaces, List<KanbanLane> lanes});

/// Persistence boundary for workspaces, lanes, and members.
///
/// Implementations return `null` from fetch methods when they hold no
/// persisted state (offline mode), in which case callers keep their
/// in-memory state.
abstract class WorkspaceRepository {
  bool get isPersistent;

  Future<WorkspacesSnapshot?> fetchWorkspaces({
    required String userId,
    required String email,
  });

  Future<List<KanbanLane>?> fetchLanes(String workspaceId);

  Future<List<WorkspaceMember>?> fetchMembers(String workspaceId);

  Future<Workspace?> fetchWorkspace(String workspaceId);

  Future<WorkspaceSnapshot?> createWorkspace({
    required String name,
    required String adminId,
    required String adminEmail,
  });

  /// Permanently removes the workspace; tasks, lanes, members, subtasks and
  /// activity logs are removed by the database cascade. Admin-only (RLS).
  Future<void> deleteWorkspace(String workspaceId);

  /// True when the signed-in user may enter the app: the site admin, still
  /// allowlisted, or a member of at least one workspace. Revoked members
  /// (workspace deleted, allowlist entry removed) get false.
  Future<bool> canAccessApp();

  /// True when the signed-in user may create a workspace: the site admin, or
  /// allowlisted and not a plain member of any workspace.
  Future<bool> canCreateWorkspace();

  Future<void> updateAutoArchiveDays(String workspaceId, int days);

  Future<void> updateShowArchivedTasks(String workspaceId, bool show);

  /// Saves the admin-chosen auto-expiry lanes. A null/absent list means the
  /// selection was never configured (legacy title-based fallback applies);
  /// an empty list disables auto-expiry.
  Future<void> updateAutoExpiryLaneIds(String workspaceId, List<String> laneIds);

  Future<void> addLane(KanbanLane lane);

  Future<void> updateLane(KanbanLane lane);

  Future<void> deleteLane(String laneId);

  Future<void> reorderLanes(List<KanbanLane> orderedLanes);

  Future<void> inviteMember(WorkspaceMember member);

  /// Adds an email to the signup allowlist so the invited user can sign
  /// in. Gated by the same admin-only RLS policy as the allowlist table.
  Future<void> allowlistEmail(String email);

  Stream<void> watchWorkspace(String workspaceId);
}

class InMemoryWorkspaceRepository implements WorkspaceRepository {
  @override
  bool get isPersistent => false;

  @override
  Future<WorkspacesSnapshot?> fetchWorkspaces({
    required String userId,
    required String email,
  }) async =>
      null;

  @override
  Future<List<KanbanLane>?> fetchLanes(String workspaceId) async => null;

  @override
  Future<List<WorkspaceMember>?> fetchMembers(String workspaceId) async => null;

  @override
  Future<Workspace?> fetchWorkspace(String workspaceId) async => null;

  @override
  Future<WorkspaceSnapshot?> createWorkspace({
    required String name,
    required String adminId,
    required String adminEmail,
  }) async =>
      null;

  @override
  Future<void> updateAutoArchiveDays(String workspaceId, int days) async {}

  @override
  Future<void> deleteWorkspace(String workspaceId) async {}

  @override
  Future<bool> canAccessApp() async => true;

  @override
  Future<bool> canCreateWorkspace() async => true;

  @override
  Future<void> updateShowArchivedTasks(String workspaceId, bool show) async {}

  @override
  Future<void> updateAutoExpiryLaneIds(String workspaceId, List<String> laneIds) async {}

  @override
  Future<void> addLane(KanbanLane lane) async {}

  @override
  Future<void> updateLane(KanbanLane lane) async {}

  @override
  Future<void> deleteLane(String laneId) async {}

  @override
  Future<void> reorderLanes(List<KanbanLane> orderedLanes) async {}

  @override
  Future<void> inviteMember(WorkspaceMember member) async {}

  @override
  Future<void> allowlistEmail(String email) async {}

  @override
  Stream<void> watchWorkspace(String workspaceId) => const Stream.empty();
}

class SupabaseWorkspaceRepository implements WorkspaceRepository {
  final SupabaseClient _client;

  SupabaseWorkspaceRepository(this._client);

  @override
  bool get isPersistent => true;

  @override
  Future<WorkspacesSnapshot?> fetchWorkspaces({
    required String userId,
    required String email,
  }) async {
    try {
      final ownedResponse =
          await _client.from('workspaces').select().eq('admin_id', userId);
      final owned = (ownedResponse as List)
          .map((row) => Workspace.fromJson(row as Map<String, dynamic>))
          .toList();

      final memberResponse = await _client
          .from('workspace_members')
          .select('workspace_id')
          .or('user_id.eq.$userId,email.eq.$email');
      final memberWorkspaceIds = (memberResponse as List)
          .map((row) => (row as Map<String, dynamic>)['workspace_id'] as String)
          .toSet();

      final byId = <String, Workspace>{for (final ws in owned) ws.id: ws};
      if (memberWorkspaceIds.isNotEmpty) {
        final joinedResponse = await _client
            .from('workspaces')
            .select()
            .inFilter('id', memberWorkspaceIds.toList());
        for (final row in joinedResponse as List) {
          final ws = Workspace.fromJson(row as Map<String, dynamic>);
          byId[ws.id] = ws;
        }
      }

      final workspaces = byId.values.toList();
      final members = <WorkspaceMember>[];
      for (final ws in workspaces) {
        final wsMembers = await fetchMembers(ws.id);
        if (wsMembers != null) members.addAll(wsMembers);
      }

      final withMembers = [
        for (final ws in workspaces)
          ws.copyWith(
            members: members.where((m) => m.workspaceId == ws.id).toList(),
          ),
      ];

      final lanes = workspaces.isEmpty
          ? <KanbanLane>[]
          : await fetchLanes(workspaces.first.id) ?? [];

      return (workspaces: withMembers, lanes: lanes);
    } catch (e) {
      debugPrint('Workspace fetch error: $e');
      return null;
    }
  }

  @override
  Future<List<WorkspaceMember>?> fetchMembers(String workspaceId) async {
    try {
      final response = await _client
          .from('workspace_members')
          .select()
          .eq('workspace_id', workspaceId);
      return (response as List)
          .map((row) => WorkspaceMember.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Member fetch error: $e');
      return null;
    }
  }

  @override
  Future<List<KanbanLane>?> fetchLanes(String workspaceId) async {
    try {
      final response = await _client
          .from('workspace_lanes')
          .select()
          .eq('workspace_id', workspaceId)
          .order('order_index', ascending: true);
      final lanes = (response as List).map((row) => KanbanLane.fromJson(row as Map<String, dynamic>)).toList();
      lanes.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return lanes;
    } catch (e) {
      debugPrint('Lane fetch error: $e');
      return null;
    }
  }

  @override
  Future<Workspace?> fetchWorkspace(String workspaceId) async {
    try {
      final response = await _client
          .from('workspaces')
          .select()
          .eq('id', workspaceId)
          .maybeSingle();
      if (response == null) return null;
      return Workspace.fromJson(response);
    } catch (e) {
      debugPrint('Workspace row fetch error: $e');
      return null;
    }
  }

  @override
  Future<WorkspaceSnapshot?> createWorkspace({
    required String name,
    required String adminId,
    required String adminEmail,
  }) async {
    try {
      final id = _uuid.v4();
      await _client.from('workspaces').insert({
        'id': id,
        'name': name,
        'admin_id': adminId,
        'auto_archive_days': 14,
      });

      final lanes = await fetchLanes(id) ?? [];
      final members = await fetchMembers(id) ?? [
        WorkspaceMember(
          id: _uuid.v4(),
          workspaceId: id,
          email: adminEmail,
          role: UserRole.admin,
        ),
      ];

      return (
        workspace: Workspace(
          id: id,
          name: name,
          adminId: adminId,
          members: members,
        ),
        lanes: lanes,
      );
    } catch (e) {
      debugPrint('Workspace create error: $e');
      return null;
    }
  }

  @override
  Future<void> deleteWorkspace(String workspaceId) async {
    try {
      await _client.from('workspaces').delete().eq('id', workspaceId);
    } catch (e) {
      debugPrint('Workspace delete error: $e');
    }
  }

  @override
  Future<bool> canAccessApp() async {
    try {
      return await _client.rpc('can_access_app') == true;
    } catch (e) {
      // Fail open so a transient RPC error never locks users out; the
      // database triggers remain the hard backstop.
      debugPrint('can_access_app error: $e');
      return true;
    }
  }

  @override
  Future<bool> canCreateWorkspace() async {
    try {
      return await _client.rpc('can_create_workspace') == true;
    } catch (e) {
      debugPrint('can_create_workspace error: $e');
      return true;
    }
  }

  @override
  Future<void> updateAutoArchiveDays(String workspaceId, int days) async {
    try {
      await _client
          .from('workspaces')
          .update({'auto_archive_days': days}).eq('id', workspaceId);
    } catch (e) {
      debugPrint('Workspace update error: $e');
    }
  }

  @override
  Future<void> updateShowArchivedTasks(String workspaceId, bool show) async {
    try {
      await _client
          .from('workspaces')
          .update({'show_archived_tasks': show}).eq('id', workspaceId);
    } catch (e) {
      debugPrint('Workspace update error: $e');
    }
  }

  @override
  Future<void> updateAutoExpiryLaneIds(String workspaceId, List<String> laneIds) async {
    try {
      await _client
          .from('workspaces')
          .update({'auto_expiry_lane_ids': laneIds}).eq('id', workspaceId);
    } catch (e) {
      debugPrint('Workspace update error: $e');
    }
  }

  @override
  Future<void> addLane(KanbanLane lane) async {
    try {
      await _client.from('workspace_lanes').insert(lane.toJson());
    } catch (e) {
      debugPrint('Lane create error: $e');
    }
  }

  @override
  Future<void> updateLane(KanbanLane lane) async {
    try {
      await _client
          .from('workspace_lanes')
          .update({'title': lane.title, 'color_hex': lane.colorHex})
          .eq('id', lane.id);
    } catch (e) {
      debugPrint('Lane update error: $e');
    }
  }

  @override
  Future<void> deleteLane(String laneId) async {
    try {
      await _client.from('workspace_lanes').delete().eq('id', laneId);
    } catch (e) {
      debugPrint('Lane delete error: $e');
    }
  }

  @override
  Future<void> reorderLanes(List<KanbanLane> orderedLanes) async {
    try {
      for (final lane in orderedLanes) {
        await _client
            .from('workspace_lanes')
            .update({'order_index': lane.orderIndex}).eq('id', lane.id);
      }
    } catch (e) {
      debugPrint('Lane reorder error: $e');
    }
  }

  @override
  Future<void> inviteMember(WorkspaceMember member) async {
    try {
      await _client.from('workspace_members').insert(member.toJson());
    } catch (e) {
      debugPrint('Member invite error: $e');
    }
  }

  @override
  Future<void> allowlistEmail(String email) async {
    try {
      await _client.from('allowed_signup_emails').upsert({
        'email': email.toLowerCase(),
      });
    } catch (e) {
      debugPrint('Signup allowlist error: $e');
    }
  }

  @override
  Stream<void> watchWorkspace(String workspaceId) {
    final controller = StreamController<void>();
    final channel = _client
        .channel('workspace-$workspaceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workspace_lanes',
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
          table: 'workspace_members',
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
          table: 'workspaces',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
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

final workspaceRepositoryProvider = Provider<WorkspaceRepository>((ref) {
  final client = SupabaseService.instance.client;
  if (client == null) return InMemoryWorkspaceRepository();
  // The demo sandbox user stays fully in-memory; real sign-ins use Supabase.
  if (ref.watch(isDemoUserProvider)) return InMemoryWorkspaceRepository();
  return SupabaseWorkspaceRepository(client);
});
