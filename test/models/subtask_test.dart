import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/models/subtask.dart';

void main() {
  group('Subtask', () {
    test('roundtrips through JSON', () {
      final subtask = Subtask(
        id: 'st-1',
        taskId: 'task-1',
        title: 'Write tests',
        isCompleted: true,
        orderIndex: 2,
      );

      final restored = Subtask.fromJson(subtask.toJson());

      expect(restored.id, subtask.id);
      expect(restored.taskId, subtask.taskId);
      expect(restored.title, subtask.title);
      expect(restored.isCompleted, subtask.isCompleted);
      expect(restored.orderIndex, subtask.orderIndex);
    });

    test('defaults isCompleted and orderIndex when missing', () {
      final subtask = Subtask.fromJson({
        'id': 'st-1',
        'task_id': 'task-1',
        'title': 'Write tests',
      });
      expect(subtask.isCompleted, false);
      expect(subtask.orderIndex, 0);
    });

    test('copyWith overrides requested fields only', () {
      final subtask = Subtask(
        id: 'st-1',
        taskId: 'task-1',
        title: 'Write tests',
        isCompleted: false,
        orderIndex: 1,
      );

      final updated = subtask.copyWith(title: 'Done', isCompleted: true);

      expect(updated.id, subtask.id);
      expect(updated.taskId, subtask.taskId);
      expect(updated.title, 'Done');
      expect(updated.isCompleted, true);
      expect(updated.orderIndex, 1);
    });
  });
}
