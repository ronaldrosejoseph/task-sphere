import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/models/lane.dart';

void main() {
  group('KanbanLane color', () {
    test('parses 6-digit hex colors', () {
      final lane = KanbanLane(
        id: 'l1',
        workspaceId: 'ws1',
        title: 'To Do',
        colorHex: '#3B82F6',
      );
      expect(lane.color, const Color(0xFF3B82F6));
    });

    test('falls back to default indigo on invalid hex', () {
      final lane = KanbanLane(
        id: 'l1',
        workspaceId: 'ws1',
        title: 'To Do',
        colorHex: 'not-a-color',
      );
      expect(lane.color, const Color(0xFF6366F1));
    });

    test('falls back when colorHex is missing', () {
      final lane = KanbanLane.fromJson({
        'id': 'l1',
        'workspace_id': 'ws1',
        'title': 'To Do',
      });
      expect(lane.colorHex, '#6366F1');
      expect(lane.color, const Color(0xFF6366F1));
    });
  });

  group('KanbanLane JSON', () {
    test('roundtrips all fields', () {
      final lane = KanbanLane(
        id: 'l1',
        workspaceId: 'ws1',
        title: 'In Review',
        colorHex: '#EC4899',
        orderIndex: 3,
        isDefault: false,
      );

      final restored = KanbanLane.fromJson(lane.toJson());

      expect(restored.id, lane.id);
      expect(restored.workspaceId, lane.workspaceId);
      expect(restored.title, lane.title);
      expect(restored.colorHex, lane.colorHex);
      expect(restored.orderIndex, lane.orderIndex);
      expect(restored.isDefault, lane.isDefault);
    });

    test('defaults orderIndex and isDefault when missing', () {
      final lane = KanbanLane.fromJson({
        'id': 'l1',
        'workspace_id': 'ws1',
        'title': 'To Do',
      });
      expect(lane.orderIndex, 0);
      expect(lane.isDefault, false);
    });
  });

  group('KanbanLane copyWith', () {
    test('keeps identity and overrides requested fields', () {
      final lane = KanbanLane(
        id: 'l1',
        workspaceId: 'ws1',
        title: 'To Do',
        colorHex: '#3B82F6',
        orderIndex: 0,
        isDefault: true,
      );

      final updated = lane.copyWith(title: 'Backlog', orderIndex: 2);

      expect(updated.id, lane.id);
      expect(updated.workspaceId, lane.workspaceId);
      expect(updated.title, 'Backlog');
      expect(updated.colorHex, lane.colorHex);
      expect(updated.orderIndex, 2);
      expect(updated.isDefault, true);
    });
  });
}
