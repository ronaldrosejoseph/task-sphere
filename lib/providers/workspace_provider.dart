import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/workspace.dart';
import '../models/lane.dart';
import '../core/services/supabase_service.dart';

const _uuid = Uuid();

final activeWorkspaceProvider = StateNotifierProvider<WorkspaceNotifier, WorkspaceState>((ref) {
  return WorkspaceNotifier();
});

class WorkspaceState {
  final Workspace activeWorkspace;
  final List<Workspace> allWorkspaces;
  final List<KanbanLane> lanes;
  final bool isLoading;

  WorkspaceState({
    required this.activeWorkspace,
    required this.allWorkspaces,
    required this.lanes,
    this.isLoading = false,
  });

  WorkspaceState copyWith({
    Workspace? activeWorkspace,
    List<Workspace>? allWorkspaces,
    List<KanbanLane>? lanes,
    bool? isLoading,
  }) {
    return WorkspaceState(
      activeWorkspace: activeWorkspace ?? this.activeWorkspace,
      allWorkspaces: allWorkspaces ?? this.allWorkspaces,
      lanes: lanes ?? this.lanes,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class WorkspaceNotifier extends StateNotifier<WorkspaceState> {
  WorkspaceNotifier() : super(_initialState());

  static WorkspaceState _initialState() {
    final defaultWs = Workspace(
      id: 'ws-demo-001',
      name: 'Engineering & Design Team',
      adminId: 'demo-user-123',
      autoArchiveDays: 14,
      members: [
        WorkspaceMember(
          id: 'mem-1',
          workspaceId: 'ws-demo-001',
          userId: 'demo-user-123',
          email: 'alex.admin@tasksphere.app',
          role: UserRole.admin,
        ),
        WorkspaceMember(
          id: 'mem-2',
          workspaceId: 'ws-demo-001',
          userId: 'user-456',
          email: 'sarah.designer@tasksphere.app',
          role: UserRole.member,
        ),
        WorkspaceMember(
          id: 'mem-3',
          workspaceId: 'ws-demo-001',
          userId: 'user-789',
          email: 'dev.team@tasksphere.app',
          role: UserRole.member,
        ),
      ],
    );

    final defaultLanes = [
      KanbanLane(id: 'lane-1', workspaceId: defaultWs.id, title: 'To Do', colorHex: '#3B82F6', orderIndex: 0, isDefault: true),
      KanbanLane(id: 'lane-2', workspaceId: defaultWs.id, title: 'In Progress', colorHex: '#F59E0B', orderIndex: 1, isDefault: true),
      KanbanLane(id: 'lane-3', workspaceId: defaultWs.id, title: 'Partially Done', colorHex: '#8B5CF6', orderIndex: 2, isDefault: true),
      KanbanLane(id: 'lane-4', workspaceId: defaultWs.id, title: 'Done', colorHex: '#10B981', orderIndex: 3, isDefault: true),
      KanbanLane(id: 'lane-5', workspaceId: defaultWs.id, title: 'Wont Do', colorHex: '#EF4444', orderIndex: 4, isDefault: true),
    ];

    return WorkspaceState(
      activeWorkspace: defaultWs,
      allWorkspaces: [defaultWs],
      lanes: defaultLanes,
    );
  }

  void createWorkspace(String name, String adminId) {
    final wsId = _uuid.v4();
    final newWs = Workspace(
      id: wsId,
      name: name,
      adminId: adminId,
      members: [
        WorkspaceMember(
          id: _uuid.v4(),
          workspaceId: wsId,
          userId: adminId,
          email: 'admin@tasksphere.app',
          role: UserRole.admin,
        )
      ],
    );

    final newLanes = [
      KanbanLane(id: _uuid.v4(), workspaceId: newWs.id, title: 'To Do', colorHex: '#3B82F6', orderIndex: 0, isDefault: true),
      KanbanLane(id: _uuid.v4(), workspaceId: newWs.id, title: 'In Progress', colorHex: '#F59E0B', orderIndex: 1, isDefault: true),
      KanbanLane(id: _uuid.v4(), workspaceId: newWs.id, title: 'Partially Done', colorHex: '#8B5CF6', orderIndex: 2, isDefault: true),
      KanbanLane(id: _uuid.v4(), workspaceId: newWs.id, title: 'Done', colorHex: '#10B981', orderIndex: 3, isDefault: true),
      KanbanLane(id: _uuid.v4(), workspaceId: newWs.id, title: 'Wont Do', colorHex: '#EF4444', orderIndex: 4, isDefault: true),
    ];

    state = state.copyWith(
      activeWorkspace: newWs,
      allWorkspaces: [...state.allWorkspaces, newWs],
      lanes: newLanes,
    );
  }

  void switchWorkspace(Workspace ws) {
    state = state.copyWith(activeWorkspace: ws);
  }

  // --- Admin Lane Customization ---
  void addLane(String title, Color color) {
    final hex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
    final newLane = KanbanLane(
      id: _uuid.v4(),
      workspaceId: state.activeWorkspace.id,
      title: title,
      colorHex: hex,
      orderIndex: state.lanes.length,
      isDefault: false,
    );

    state = state.copyWith(lanes: [...state.lanes, newLane]);
  }

  void updateLane(String laneId, String newTitle, Color newColor) {
    final hex = '#${newColor.value.toRadixString(16).substring(2).toUpperCase()}';
    final updatedLanes = state.lanes.map((l) {
      if (l.id == laneId) {
        return l.copyWith(title: newTitle, colorHex: hex);
      }
      return l;
    }).toList();

    state = state.copyWith(lanes: updatedLanes);
  }

  void reorderLanes(int oldIndex, int newIndex) {
    final list = List<KanbanLane>.from(state.lanes);
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    final reindexed = list.asMap().entries.map((entry) {
      return entry.value.copyWith(orderIndex: entry.key);
    }).toList();

    state = state.copyWith(lanes: reindexed);
  }

  void deleteLane(String laneId) {
    final updatedLanes = state.lanes.where((l) => l.id != laneId).toList();
    state = state.copyWith(lanes: updatedLanes);
  }

  // --- Workspace Settings ---
  void updateAutoArchiveThreshold(int days) {
    final updatedWs = state.activeWorkspace.copyWith(autoArchiveDays: days);
    state = state.copyWith(activeWorkspace: updatedWs);
  }

  void inviteMember(String email, UserRole role) {
    final newMember = WorkspaceMember(
      id: _uuid.v4(),
      workspaceId: state.activeWorkspace.id,
      email: email,
      role: role,
    );
    final updatedMembers = [...state.activeWorkspace.members, newMember];
    final updatedWs = state.activeWorkspace.copyWith(members: updatedMembers);
    state = state.copyWith(activeWorkspace: updatedWs);
  }
}
