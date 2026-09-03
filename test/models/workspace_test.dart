import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/models/lane.dart';
import 'package:task_sphere/models/workspace.dart';

List<KanbanLane> _lanes(List<(String, String)> idTitle) => [
      for (final (id, title) in idTitle)
        KanbanLane(id: id, workspaceId: 'ws1', title: title),
    ];

void main() {
  group('WorkspaceMember', () {
    test('parses admin role case-insensitively', () {
      final member = WorkspaceMember.fromJson({
        'id': 'm1',
        'workspace_id': 'ws1',
        'user_id': 'u1',
        'email': 'admin@example.com',
        'role': 'ADMIN',
      });
      expect(member.role, UserRole.admin);
    });

    test('parses non-admin roles as member', () {
      final member = WorkspaceMember.fromJson({
        'id': 'm1',
        'workspace_id': 'ws1',
        'email': 'member@example.com',
        'role': 'member',
      });
      expect(member.role, UserRole.member);
    });

    test('falls back to member role and placeholder email', () {
      final member = WorkspaceMember.fromJson({
        'id': 'm1',
        'workspace_id': 'ws1',
        'role': 'superuser',
      });
      expect(member.role, UserRole.member);
      expect(member.email, 'member@example.com');
    });

    test('roundtrips through JSON', () {
      final member = WorkspaceMember(
        id: 'm1',
        workspaceId: 'ws1',
        userId: 'u1',
        email: 'alex@example.com',
        role: UserRole.admin,
      );

      final restored = WorkspaceMember.fromJson(member.toJson());

      expect(restored.id, member.id);
      expect(restored.workspaceId, member.workspaceId);
      expect(restored.userId, member.userId);
      expect(restored.email, member.email);
      expect(restored.role, member.role);
    });
  });

  group('Workspace', () {
    test('roundtrips through JSON', () {
      final workspace = Workspace(
        id: 'ws1',
        name: 'Engineering',
        adminId: 'admin-1',
        autoArchiveDays: 30,
        createdAt: DateTime.utc(2026, 8, 1),
      );

      final restored = Workspace.fromJson(workspace.toJson());

      expect(restored.id, workspace.id);
      expect(restored.name, workspace.name);
      expect(restored.adminId, workspace.adminId);
      expect(restored.autoArchiveDays, 30);
      expect(restored.createdAt, workspace.createdAt);
    });

    test('falls back to defaults for missing fields', () {
      final workspace = Workspace.fromJson({'id': 'ws1'});
      expect(workspace.name, 'Default Workspace');
      expect(workspace.adminId, '');
      expect(workspace.autoArchiveDays, 14);
    });

    test('copyWith overrides requested fields only', () {
      final workspace = Workspace(
        id: 'ws1',
        name: 'Engineering',
        adminId: 'admin-1',
        autoArchiveDays: 14,
        members: [
          WorkspaceMember(
            id: 'm1',
            workspaceId: 'ws1',
            email: 'alex@example.com',
            role: UserRole.admin,
          ),
        ],
      );

      final updated = workspace.copyWith(name: 'Design', autoArchiveDays: 7);

      expect(updated.id, workspace.id);
      expect(updated.adminId, workspace.adminId);
      expect(updated.name, 'Design');
      expect(updated.autoArchiveDays, 7);
      expect(updated.members, workspace.members);
      expect(updated.createdAt, workspace.createdAt);
    });
  });

  group('Workspace auto-expiry lanes', () {
    Workspace ws({List<String>? autoExpiryLaneIds}) => Workspace(
          id: 'ws1',
          name: 'Engineering',
          adminId: 'admin-1',
          autoExpiryLaneIds: autoExpiryLaneIds,
        );

    test('JSON roundtrip preserves the configured lane ids', () {
      final workspace = ws(autoExpiryLaneIds: ['lane-4', 'lane-5']);
      final restored = Workspace.fromJson(workspace.toJson());
      expect(restored.autoExpiryLaneIds, ['lane-4', 'lane-5']);
    });

    test('JSON roundtrip preserves an explicit empty selection', () {
      final restored = Workspace.fromJson(ws(autoExpiryLaneIds: []).toJson());
      expect(restored.autoExpiryLaneIds, isEmpty);
    });

    test('missing json key parses as null (unconfigured)', () {
      final workspace = Workspace.fromJson({'id': 'ws1'});
      expect(workspace.autoExpiryLaneIds, isNull);
    });

    test('copyWith carries the selection through and overrides it', () {
      final original = ws();
      expect(original.copyWith(autoExpiryLaneIds: ['lane-4']).autoExpiryLaneIds,
          ['lane-4']);
      expect(original.autoExpiryLaneIds, isNull);
    });

    test('unconfigured workspace resolves Done/Wont Do lanes by title', () {
      final resolved = ws().resolvedAutoExpiryLaneIds(_lanes([
        ('lane-1', 'To Do'),
        ('lane-4', 'Done'),
        ('lane-5', 'Wont Do'),
      ]));
      expect(resolved, ['lane-4', 'lane-5']);
    });

    test('title fallback matches case-insensitively', () {
      final resolved = ws().resolvedAutoExpiryLaneIds(_lanes([
        ('lane-4', 'DONE'),
        ('lane-5', 'wont do'),
      ]));
      expect(resolved, ['lane-4', 'lane-5']);
    });

    test('renamed lanes break the legacy fallback (the bug the setting fixes)', () {
      final resolved = ws().resolvedAutoExpiryLaneIds(_lanes([
        ('lane-4', 'Finished'),
        ('lane-5', 'Closed'),
      ]));
      expect(resolved, isEmpty);
    });

    test('a stored selection wins over lane titles', () {
      final resolved = ws(autoExpiryLaneIds: ['lane-4'])
          .resolvedAutoExpiryLaneIds(_lanes([('lane-4', 'Finished')]));
      expect(resolved, ['lane-4']);
    });

    test('an explicit empty selection disables auto-expiry', () {
      final resolved = ws(autoExpiryLaneIds: []).resolvedAutoExpiryLaneIds(
          _lanes([('lane-4', 'Done'), ('lane-5', 'Wont Do')]));
      expect(resolved, isEmpty);
    });
  });
}
