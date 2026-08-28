import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/models/workspace.dart';

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
}
