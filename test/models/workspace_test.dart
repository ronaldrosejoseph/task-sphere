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

    test('roundtrips the display name through JSON', () {
      final member = WorkspaceMember(
        id: 'm1',
        workspaceId: 'ws1',
        email: 'alex@example.com',
        role: UserRole.admin,
        displayName: 'Alex Morgan',
      );

      final restored = WorkspaceMember.fromJson(member.toJson());
      expect(restored.displayName, 'Alex Morgan');
    });

    test('missing display name key parses as null', () {
      final member = WorkspaceMember.fromJson({
        'id': 'm1',
        'workspace_id': 'ws1',
        'email': 'alex@example.com',
        'role': 'admin',
      });
      expect(member.displayName, isNull);
    });
  });

  group('displayLabel', () {
    WorkspaceMember member({String? displayName}) => WorkspaceMember(
          id: 'm1',
          workspaceId: 'ws1',
          email: 'sarah.designer@example.com',
          role: UserRole.member,
          displayName: displayName,
        );

    test('uses the display name when set', () {
      expect(member(displayName: 'Sarah Designer').displayLabel, 'Sarah Designer');
    });

    test('trims the display name', () {
      expect(member(displayName: '  Sarah  ').displayLabel, 'Sarah');
    });

    test('falls back to the email prefix when unset or empty', () {
      expect(member().displayLabel, 'sarah.designer');
      expect(member(displayName: '   ').displayLabel, 'sarah.designer');
    });
  });

  group('memberDisplayLabel', () {
    final members = [
      WorkspaceMember(
        id: 'm1',
        workspaceId: 'ws1',
        email: 'alex.admin@example.com',
        role: UserRole.admin,
        displayName: 'Alex Morgan',
      ),
      WorkspaceMember(
        id: 'm2',
        workspaceId: 'ws1',
        email: 'sarah.designer@example.com',
        role: UserRole.member,
      ),
    ];

    test('resolves the label for a matching member case-insensitively', () {
      expect(memberDisplayLabel(members, 'ALEX.ADMIN@example.com'), 'Alex Morgan');
      expect(memberDisplayLabel(members, 'sarah.designer@example.com'),
          'sarah.designer');
    });

    test('returns null when no member matches or email is missing', () {
      expect(memberDisplayLabel(members, 'ghost@example.com'), isNull);
      expect(memberDisplayLabel(members, null), isNull);
    });
  });

  group('memberDisplayName', () {
    final members = [
      WorkspaceMember(
        id: 'm1',
        workspaceId: 'ws1',
        email: 'alex.admin@example.com',
        role: UserRole.admin,
        displayName: 'Alex Morgan',
      ),
      WorkspaceMember(
        id: 'm2',
        workspaceId: 'ws1',
        email: 'sarah.designer@example.com',
        role: UserRole.member,
        displayName: '   ',
      ),
      WorkspaceMember(
        id: 'm3',
        workspaceId: 'ws1',
        email: 'dev.team@example.com',
        role: UserRole.member,
      ),
    ];

    test('returns the configured name case-insensitively', () {
      expect(memberDisplayName(members, 'ALEX.ADMIN@example.com'), 'Alex Morgan');
    });

    test('never falls back to the email prefix', () {
      // No name set or only whitespace: null so callers can use the account
      // name instead of exposing the email prefix.
      expect(memberDisplayName(members, 'sarah.designer@example.com'), isNull);
      expect(memberDisplayName(members, 'dev.team@example.com'), isNull);
    });

    test('returns null when no member matches or email is missing', () {
      expect(memberDisplayName(members, 'ghost@example.com'), isNull);
      expect(memberDisplayName(members, null), isNull);
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
          autoExpiryLaneIds: autoExpiryLaneIds ?? const [],
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

    test('missing json key parses as an empty selection', () {
      final workspace = Workspace.fromJson({'id': 'ws1'});
      expect(workspace.autoExpiryLaneIds, isEmpty);
    });

    test('unconfigured workspace has auto-expiry disabled (no title fallback)', () {
      final workspace = ws();
      expect(workspace.autoExpiryLaneIds, isEmpty);
    });

    test('copyWith carries the selection through and overrides it', () {
      final original = ws();
      expect(original.copyWith(autoExpiryLaneIds: ['lane-4']).autoExpiryLaneIds,
          ['lane-4']);
      expect(original.autoExpiryLaneIds, isEmpty);
    });
  });
}
