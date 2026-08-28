import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/models/activity_log.dart';

void main() {
  group('ActivityLog', () {
    test('roundtrips through JSON', () {
      final log = ActivityLog(
        id: 'log-1',
        taskId: 'task-1',
        workspaceId: 'ws-1',
        userName: 'Alex',
        action: 'Moved task to Done',
        createdAt: DateTime.utc(2026, 8, 20, 9, 30),
      );

      final restored = ActivityLog.fromJson(log.toJson());

      expect(restored.id, log.id);
      expect(restored.taskId, log.taskId);
      expect(restored.workspaceId, log.workspaceId);
      expect(restored.userName, log.userName);
      expect(restored.action, log.action);
      expect(restored.createdAt, log.createdAt);
    });

    test('defaults createdAt to now', () {
      final before = DateTime.now();
      final log = ActivityLog(id: 'log-1', workspaceId: 'ws-1', userName: 'A', action: 'x');
      final after = DateTime.now();
      expect(log.createdAt.isBefore(before), isFalse);
      expect(log.createdAt.isAfter(after), isFalse);
    });

    test('falls back for missing userName and action', () {
      final log = ActivityLog.fromJson({'id': 'log-1', 'workspace_id': 'ws-1'});
      expect(log.userName, 'User');
      expect(log.action, 'performed action');
    });
  });
}
