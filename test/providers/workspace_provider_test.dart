import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/models/workspace.dart';
import 'package:task_sphere/providers/workspace_provider.dart';

ProviderContainer makeContainer() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('WorkspaceNotifier initial state', () {
    test('loads the demo workspace with five default lanes', () {
      final state = makeContainer().read(activeWorkspaceProvider);
      expect(state.activeWorkspace.name, 'Engineering & Design Team');
      expect(state.allWorkspaces.length, 1);
      expect(state.lanes.length, 5);
      expect(state.lanes.map((l) => l.title).toList(),
          ['To Do', 'In Progress', 'Partially Done', 'Done', 'Wont Do']);
      expect(state.lanes.every((l) => l.isDefault), isTrue);
      expect(state.activeWorkspace.members.length, 3);
      expect(state.activeWorkspace.members.first.role, UserRole.admin);
    });
  });

  group('lane management', () {
    test('addLane appends a custom lane with hex color', () {
      final container = makeContainer();
      final notifier = container.read(activeWorkspaceProvider.notifier);

      notifier.addLane('In Review', const Color(0xFFEC4899));

      final lanes = container.read(activeWorkspaceProvider).lanes;
      expect(lanes.length, 6);
      final added = lanes.last;
      expect(added.title, 'In Review');
      expect(added.colorHex, '#EC4899');
      expect(added.orderIndex, 5);
      expect(added.isDefault, isFalse);
    });

    test('updateLane changes title and color of the matching lane', () {
      final container = makeContainer();
      final notifier = container.read(activeWorkspaceProvider.notifier);

      notifier.updateLane('lane-1', 'Backlog', const Color(0xFF10B981));

      final lane = container.read(activeWorkspaceProvider).lanes.first;
      expect(lane.title, 'Backlog');
      expect(lane.colorHex, '#10B981');
    });

    test('reorderLanes moves the lane and reindexes orderIndex', () {
      final container = makeContainer();
      final notifier = container.read(activeWorkspaceProvider.notifier);
      final titlesBefore =
          container.read(activeWorkspaceProvider).lanes.map((l) => l.title).toList();

      // onReorderItem-style call: newIndex is the final insertion position.
      notifier.reorderLanes(0, 3);

      final lanes = container.read(activeWorkspaceProvider).lanes;
      expect(lanes.map((l) => l.title).toList(), [
        titlesBefore[1],
        titlesBefore[2],
        titlesBefore[3],
        titlesBefore[0],
        titlesBefore[4],
      ]);
      for (var i = 0; i < lanes.length; i++) {
        expect(lanes[i].orderIndex, i);
      }
    });

    test('reorderLanes moving an item down one position swaps neighbours', () {
      final container = makeContainer();
      final notifier = container.read(activeWorkspaceProvider.notifier);

      notifier.reorderLanes(2, 1);

      final lanes = container.read(activeWorkspaceProvider).lanes;
      expect(lanes.map((l) => l.title).toList(),
          ['To Do', 'Partially Done', 'In Progress', 'Done', 'Wont Do']);
      for (var i = 0; i < lanes.length; i++) {
        expect(lanes[i].orderIndex, i);
      }
    });

    test('deleteLane removes the matching lane', () {
      final container = makeContainer();
      final notifier = container.read(activeWorkspaceProvider.notifier);

      notifier.addLane('Temporary', const Color(0xFFEC4899));
      final tempId =
          container.read(activeWorkspaceProvider).lanes.last.id;

      notifier.deleteLane(tempId);

      final lanes = container.read(activeWorkspaceProvider).lanes;
      expect(lanes.any((l) => l.id == tempId), isFalse);
      expect(lanes.length, 5);
    });
  });

  group('workspace management', () {
    test('createWorkspace switches to the new workspace with fresh lanes', () async {
      final container = makeContainer();
      final notifier = container.read(activeWorkspaceProvider.notifier);

      await notifier.createWorkspace('Mobile Team', 'admin-1', 'admin@example.com');

      final state = container.read(activeWorkspaceProvider);
      expect(state.activeWorkspace.name, 'Mobile Team');
      expect(state.allWorkspaces.length, 2);
      expect(state.lanes.length, 5);
      expect(state.lanes.every((l) => l.workspaceId == state.activeWorkspace.id), isTrue);
    });

    test('createWorkspace admin member gets the new workspace id', () async {
      final container = makeContainer();
      final notifier = container.read(activeWorkspaceProvider.notifier);

      await notifier.createWorkspace('Mobile Team', 'admin-1', 'admin@example.com');

      final state = container.read(activeWorkspaceProvider);
      final admin = state.activeWorkspace.members.single;
      expect(admin.workspaceId, state.activeWorkspace.id);
      expect(admin.userId, 'admin-1');
      expect(admin.role, UserRole.admin);
    });

    test('switchWorkspace changes only the active workspace', () async {
      final container = makeContainer();
      final notifier = container.read(activeWorkspaceProvider.notifier);

      await notifier.createWorkspace('Mobile Team', 'admin-1', 'admin@example.com');
      final all = container.read(activeWorkspaceProvider).allWorkspaces;
      final original = all.firstWhere((ws) => ws.name == 'Engineering & Design Team');

      notifier.switchWorkspace(original);

      final state = container.read(activeWorkspaceProvider);
      expect(state.activeWorkspace.name, 'Engineering & Design Team');
      expect(state.allWorkspaces.length, 2);
    });

    test('inviteMember appends a member to the active workspace', () {
      final container = makeContainer();
      final notifier = container.read(activeWorkspaceProvider.notifier);
      final countBefore = container.read(activeWorkspaceProvider).activeWorkspace.members.length;

      notifier.inviteMember('new.member@example.com', UserRole.member);

      final members = container.read(activeWorkspaceProvider).activeWorkspace.members;
      expect(members.length, countBefore + 1);
      final invited = members.last;
      expect(invited.email, 'new.member@example.com');
      expect(invited.role, UserRole.member);
    });

    test('updateAutoArchiveThreshold changes only the active workspace', () {
      final container = makeContainer();
      final notifier = container.read(activeWorkspaceProvider.notifier);

      notifier.updateAutoArchiveThreshold(30);

      final state = container.read(activeWorkspaceProvider);
      expect(state.activeWorkspace.autoArchiveDays, 30);
      expect(
        state.allWorkspaces.firstWhere((ws) => ws.id == state.activeWorkspace.id).autoArchiveDays,
        isNot(30),
      );
    });
  });
}
