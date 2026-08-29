import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/repositories/workspace_repository.dart';
import '../models/workspace.dart';
import '../models/lane.dart';
import 'auth_provider.dart';

const _uuid = Uuid();

final activeWorkspaceProvider = StateNotifierProvider<WorkspaceNotifier, WorkspaceState>((ref) {
  final repo = ref.watch(workspaceRepositoryProvider);
  final user = ref.read(authProvider);
  final notifier = WorkspaceNotifier(repo, user?.id, user?.email);
  notifier.loadInitialData();
  return notifier;
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
  final WorkspaceRepository _repo;
  final String? _userId;
  final String? _userEmail;

  StreamSubscription<void>? _workspaceSub;
  Timer? _reloadDebounce;

  WorkspaceNotifier(this._repo, [this._userId, this._userEmail])
      : super(_repo.isPersistent ? _loadingState() : _initialState());

  static WorkspaceState _loadingState() {
    return WorkspaceState(
      activeWorkspace: Workspace(id: 'loading', name: 'Loading…', adminId: ''),
      allWorkspaces: const [],
      lanes: const [],
      isLoading: true,
    );
  }

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

  @override
  void dispose() {
    _workspaceSub?.cancel();
    _reloadDebounce?.cancel();
    super.dispose();
  }

  Future<void> loadInitialData() async {
    if (!_repo.isPersistent) return;

    final snapshot = await _repo.fetchWorkspaces(
      userId: _userId ?? '',
      email: _userEmail ?? '',
    );
    if (snapshot == null || !mounted) return;

    if (snapshot.workspaces.isEmpty) {
      await createWorkspace('My Workspace', _userId ?? '', _userEmail ?? '');
      return;
    }

    final active = snapshot.workspaces.first;
    state = WorkspaceState(
      activeWorkspace: active,
      allWorkspaces: snapshot.workspaces,
      lanes: snapshot.lanes,
      isLoading: false,
    );
    _subscribeToWorkspace(active.id);
  }

  Future<void> createWorkspace(String name, String adminId, String adminEmail) async {
    if (_repo.isPersistent) {
      final created = await _repo.createWorkspace(
        name: name,
        adminId: adminId,
        adminEmail: adminEmail,
      );
      if (created == null || !mounted) return;
      state = state.copyWith(
        activeWorkspace: created.workspace,
        allWorkspaces: [...state.allWorkspaces, created.workspace],
        lanes: created.lanes,
        isLoading: false,
      );
      _subscribeToWorkspace(created.workspace.id);
      return;
    }

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
          email: adminEmail,
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

  Future<void> switchWorkspace(Workspace ws) async {
    state = state.copyWith(activeWorkspace: ws);
    if (!_repo.isPersistent) return;

    state = state.copyWith(lanes: const [], isLoading: true);
    final lanes = await _repo.fetchLanes(ws.id);
    if (!mounted || state.activeWorkspace.id != ws.id) return;
    state = state.copyWith(lanes: lanes ?? const [], isLoading: false);
    _subscribeToWorkspace(ws.id);
  }

  // --- Admin Lane Customization ---
  void addLane(String title, Color color) {
    final hex = '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    final newLane = KanbanLane(
      id: _uuid.v4(),
      workspaceId: state.activeWorkspace.id,
      title: title,
      colorHex: hex,
      orderIndex: state.lanes.length,
      isDefault: false,
    );

    state = state.copyWith(lanes: [...state.lanes, newLane]);
    if (_repo.isPersistent) {
      unawaited(_repo.addLane(newLane));
    }
  }

  void updateLane(String laneId, String newTitle, Color newColor) {
    final hex = '#${newColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    KanbanLane? updated;
    final updatedLanes = state.lanes.map((l) {
      if (l.id == laneId) {
        updated = l.copyWith(title: newTitle, colorHex: hex);
        return updated!;
      }
      return l;
    }).toList();

    state = state.copyWith(lanes: updatedLanes);
    if (_repo.isPersistent && updated != null) {
      unawaited(_repo.updateLane(updated!));
    }
  }

  void reorderLanes(int oldIndex, int newIndex) {
    final list = List<KanbanLane>.from(state.lanes);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    final reindexed = list.asMap().entries.map((entry) {
      return entry.value.copyWith(orderIndex: entry.key);
    }).toList();

    state = state.copyWith(lanes: reindexed);
    if (_repo.isPersistent) {
      unawaited(_repo.reorderLanes(reindexed));
    }
  }

  void deleteLane(String laneId) {
    final updatedLanes = state.lanes.where((l) => l.id != laneId).toList();
    state = state.copyWith(lanes: updatedLanes);
    if (_repo.isPersistent) {
      unawaited(_repo.deleteLane(laneId));
    }
  }

  // --- Workspace Settings ---
  void updateAutoArchiveThreshold(int days) {
    final updatedWs = state.activeWorkspace.copyWith(autoArchiveDays: days);
    state = state.copyWith(activeWorkspace: updatedWs);
    if (_repo.isPersistent) {
      unawaited(_repo.updateAutoArchiveDays(updatedWs.id, days));
    }
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
    if (_repo.isPersistent) {
      unawaited(_repo.inviteMember(newMember));
      // Let the invited user sign in without a manual SQL insert.
      unawaited(_repo.allowlistEmail(email));
    }
  }

  void _subscribeToWorkspace(String workspaceId) {
    _workspaceSub?.cancel();
    _workspaceSub = _repo.watchWorkspace(workspaceId).listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(
        const Duration(milliseconds: 300),
        () => _reloadWorkspace(workspaceId),
      );
    });
  }

  Future<void> _reloadWorkspace(String workspaceId) async {
    final lanes = await _repo.fetchLanes(workspaceId);
    final members = await _repo.fetchMembers(workspaceId);
    if (!mounted || state.activeWorkspace.id != workspaceId) return;

    if (lanes != null) {
      state = state.copyWith(lanes: lanes);
    }
    if (members != null) {
      final updatedWs = state.activeWorkspace.copyWith(members: members);
      state = state.copyWith(
        activeWorkspace: updatedWs,
        allWorkspaces: [
          for (final w in state.allWorkspaces)
            w.id == updatedWs.id ? updatedWs : w,
        ],
      );
    }
  }
}
