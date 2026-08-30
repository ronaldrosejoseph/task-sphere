import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/repositories/workspace_repository.dart';
import '../models/workspace.dart';
import '../models/lane.dart';
import '../models/user_profile.dart';
import 'auth_provider.dart';

const _uuid = Uuid();

/// The offline demo workspace. Demo seed data is only ever shown for it.
const demoWorkspaceId = 'ws-demo-001';

final activeWorkspaceProvider =
    NotifierProvider<WorkspaceNotifier, WorkspaceState>(WorkspaceNotifier.new);

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

  /// True once a real workspace exists (i.e. not the loading or empty sentinel).
  bool get hasWorkspace =>
      !isLoading &&
      activeWorkspace.id.isNotEmpty &&
      activeWorkspace.id != 'loading';

  /// Shown while data is being fetched.
  static WorkspaceState loading() {
    return WorkspaceState(
      activeWorkspace: Workspace(id: 'loading', name: 'Loading…', adminId: ''),
      allWorkspaces: const [],
      lanes: const [],
      isLoading: true,
    );
  }

  /// Shown when the signed-in user has no workspace yet.
  static WorkspaceState empty() {
    return WorkspaceState(
      activeWorkspace: Workspace(id: '', name: 'No Workspace', adminId: ''),
      allWorkspaces: const [],
      lanes: const [],
    );
  }
}

class WorkspaceNotifier extends Notifier<WorkspaceState> {
  WorkspaceRepository? _repo;
  String? _userId;
  String? _userEmail;

  StreamSubscription<void>? _workspaceSub;
  Timer? _reloadDebounce;

  /// Lanes per workspace for the in-memory (offline) path, so switching
  /// workspaces keeps each workspace's own lane set.
  final Map<String, List<KanbanLane>> _lanesByWorkspace = {};

  WorkspaceRepository get _repository {
    final repo = _repo;
    if (repo == null) {
      throw StateError('WorkspaceNotifier used before build() completed');
    }
    return repo;
  }

  @override
  WorkspaceState build() {
    _repo = ref.watch(workspaceRepositoryProvider);
    final user = ref.read(authProvider);
    _userId = user?.id;
    _userEmail = user?.email;

    ref.onDispose(() {
      _workspaceSub?.cancel();
      _reloadDebounce?.cancel();
    });

    final initial =
        _repository.isPersistent ? WorkspaceState.loading() : _initialState();
    if (!_repository.isPersistent) {
      _lanesByWorkspace[initial.activeWorkspace.id] = List.of(initial.lanes);
    }
    unawaited(loadInitialData());
    return initial;
  }

  static WorkspaceState _initialState() {
    final defaultWs = Workspace(
      id: demoWorkspaceId,
      name: 'Engineering & Design Team',
      adminId: 'demo-user-123',
      autoArchiveDays: 14,
      members: [
        WorkspaceMember(
          id: 'mem-1',
          workspaceId: demoWorkspaceId,
          userId: 'demo-user-123',
          email: 'alex.admin@tasksphere.app',
          role: UserRole.admin,
        ),
        WorkspaceMember(
          id: 'mem-2',
          workspaceId: demoWorkspaceId,
          userId: 'user-456',
          email: 'sarah.designer@tasksphere.app',
          role: UserRole.member,
        ),
        WorkspaceMember(
          id: 'mem-3',
          workspaceId: demoWorkspaceId,
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

  Future<void> loadInitialData() async {
    final repo = _repository;
    if (!repo.isPersistent) return;

    final snapshot = await repo.fetchWorkspaces(
      userId: _userId ?? '',
      email: _userEmail ?? '',
    );
    if (snapshot == null || !ref.mounted) return;

    if (snapshot.workspaces.isEmpty) {
      // First-time user: require an explicit workspace creation.
      state = WorkspaceState.empty();
      return;
    }

    final active = snapshot.workspaces.first;
    final lanes = await _ensureLanes(active.id);
    if (!ref.mounted) return;
    state = WorkspaceState(
      activeWorkspace: active,
      allWorkspaces: snapshot.workspaces,
      lanes: lanes,
      isLoading: false,
    );
    _subscribeToWorkspace(active.id);
  }

  static const _defaultLanes = [
    ('To Do', '#3B82F6'),
    ('In Progress', '#F59E0B'),
    ('Partially Done', '#8B5CF6'),
    ('Done', '#10B981'),
    ('Wont Do', '#EF4444'),
  ];

  /// Guarantees the five default lanes exist for [workspaceId], seeding them
  /// through the repository when the database has none (e.g. a workspace
  /// created before the seeding trigger existed).
  Future<List<KanbanLane>> _ensureLanes(String workspaceId) async {
    var lanes = await _repository.fetchLanes(workspaceId) ?? const [];
    if (lanes.isEmpty && _repository.isPersistent) {
      for (var i = 0; i < _defaultLanes.length; i++) {
        await _repository.addLane(KanbanLane(
          id: _uuid.v4(),
          workspaceId: workspaceId,
          title: _defaultLanes[i].$1,
          colorHex: _defaultLanes[i].$2,
          orderIndex: i,
          isDefault: true,
        ));
      }
      lanes = await _repository.fetchLanes(workspaceId) ?? const [];
    }
    return lanes;
  }

  Future<void> createWorkspace(String name, String adminId, String adminEmail) async {
    // The demo sandbox cannot create workspaces; the UI hides the entry point.
    if (ref.read(isDemoUserProvider)) return;
    final repo = _repository;
    if (repo.isPersistent) {
      final created = await repo.createWorkspace(
        name: name,
        adminId: adminId,
        adminEmail: adminEmail,
      );
      if (created == null || !ref.mounted) return;
      final lanes = await _ensureLanes(created.workspace.id);
      if (!ref.mounted) return;
      state = state.copyWith(
        activeWorkspace: created.workspace,
        allWorkspaces: [...state.allWorkspaces, created.workspace],
        lanes: lanes,
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
    _lanesByWorkspace[newWs.id] = List.of(newLanes);
  }

  /// Whether [user] is an admin of the active workspace.
  bool isAdmin(UserProfile? user) {
    if (user == null) return false;
    final ws = state.activeWorkspace;
    return ws.members.any(
      (m) =>
          m.role == UserRole.admin &&
          ((m.userId != null && m.userId!.isNotEmpty && m.userId == user.id) ||
              m.email.toLowerCase() == user.email.toLowerCase()),
    );
  }

  /// Permanently deletes [workspaceId]. Only the active workspace can be
  /// deleted from the app; the database cascade removes tasks, lanes,
  /// members, subtasks, and activity logs.
  Future<void> deleteWorkspace(String workspaceId) async {
    // The demo sandbox is read-only for creations/deletions.
    if (ref.read(isDemoUserProvider)) return;
    if (!isAdmin(ref.read(authProvider))) return;

    final repo = _repository;
    if (repo.isPersistent) {
      await repo.deleteWorkspace(workspaceId);
      if (!ref.mounted) return;
    }

    final remaining =
        state.allWorkspaces.where((w) => w.id != workspaceId).toList();
    if (remaining.isEmpty) {
      state = WorkspaceState.empty();
      return;
    }

    final next = remaining.first;
    if (workspaceId != state.activeWorkspace.id) {
      state = state.copyWith(allWorkspaces: remaining);
      return;
    }

    if (repo.isPersistent) {
      final lanes = await _ensureLanes(next.id);
      if (!ref.mounted) return;
      state = WorkspaceState(
        activeWorkspace: next,
        allWorkspaces: remaining,
        lanes: lanes,
        isLoading: false,
      );
      _subscribeToWorkspace(next.id);
    } else {
      state = state.copyWith(
        activeWorkspace: next,
        allWorkspaces: remaining,
        lanes: List.of(_lanesByWorkspace[next.id] ?? const []),
      );
    }
  }

  Future<void> switchWorkspace(Workspace ws) async {
    // Always activate the canonical instance so updated settings are kept.
    final canonical = state.allWorkspaces.firstWhere(
      (w) => w.id == ws.id,
      orElse: () => ws,
    );
    final repo = _repository;
    if (!repo.isPersistent) {
      _lanesByWorkspace[state.activeWorkspace.id] = List.of(state.lanes);
      state = state.copyWith(
        activeWorkspace: canonical,
        lanes: List.of(_lanesByWorkspace[canonical.id] ?? const []),
      );
      return;
    }
    state = state.copyWith(activeWorkspace: canonical);

    state = state.copyWith(lanes: const [], isLoading: true);
    final lanes = await _ensureLanes(ws.id);
    if (!ref.mounted || state.activeWorkspace.id != ws.id) return;
    state = state.copyWith(lanes: lanes, isLoading: false);
    _subscribeToWorkspace(ws.id);
  }

  // --- Admin Lane Customization ---
  void addLane(String title, Color color) {
    if (title.trim().isEmpty) return;
    final hex = '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    // New lanes appear at the top of the board; existing lanes shift down.
    final newLane = KanbanLane(
      id: _uuid.v4(),
      workspaceId: state.activeWorkspace.id,
      title: title,
      colorHex: hex,
      orderIndex: 0,
      isDefault: false,
    );

    final reindexed = [newLane, ...state.lanes]
        .asMap()
        .entries
        .map((e) => e.value.copyWith(orderIndex: e.key))
        .toList();

    state = state.copyWith(lanes: reindexed);
    _lanesByWorkspace[state.activeWorkspace.id] = List.of(state.lanes);
    if (_repository.isPersistent) {
      unawaited(_repository.addLane(newLane));
      // Keep the persisted order_index values contiguous.
      unawaited(_repository.reorderLanes(reindexed));
    }
  }

  void updateLane(String laneId, String newTitle, Color newColor) {
    if (newTitle.trim().isEmpty) return;
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
    _lanesByWorkspace[state.activeWorkspace.id] = List.of(state.lanes);
    if (_repository.isPersistent && updated != null) {
      unawaited(_repository.updateLane(updated!));
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
    _lanesByWorkspace[state.activeWorkspace.id] = List.of(state.lanes);
    if (_repository.isPersistent) {
      unawaited(_repository.reorderLanes(reindexed));
    }
  }

  void deleteLane(String laneId) {
    final updatedLanes = state.lanes.where((l) => l.id != laneId).toList();
    state = state.copyWith(lanes: updatedLanes);
    _lanesByWorkspace[state.activeWorkspace.id] = List.of(state.lanes);
    if (_repository.isPersistent) {
      unawaited(_repository.deleteLane(laneId));
    }
  }

  // --- Workspace Settings ---
  void updateAutoArchiveThreshold(int days) {
    final updatedWs = state.activeWorkspace.copyWith(autoArchiveDays: days);
    state = state.copyWith(
      activeWorkspace: updatedWs,
      allWorkspaces: [
        for (final w in state.allWorkspaces)
          w.id == updatedWs.id ? updatedWs : w,
      ],
    );
    if (_repository.isPersistent) {
      unawaited(_repository.updateAutoArchiveDays(updatedWs.id, days));
    }
  }

  void updateShowArchivedTasks(bool show) {
    final updatedWs = state.activeWorkspace.copyWith(showArchivedTasks: show);
    state = state.copyWith(
      activeWorkspace: updatedWs,
      allWorkspaces: [
        for (final w in state.allWorkspaces)
          w.id == updatedWs.id ? updatedWs : w,
      ],
    );
    if (_repository.isPersistent) {
      unawaited(_repository.updateShowArchivedTasks(updatedWs.id, show));
    }
  }

  void inviteMember(String email, UserRole role) {
    // The demo sandbox cannot invite members; the UI hides the entry point.
    if (ref.read(isDemoUserProvider)) return;
    final newMember = WorkspaceMember(
      id: _uuid.v4(),
      workspaceId: state.activeWorkspace.id,
      email: email,
      role: role,
    );
    final updatedMembers = [...state.activeWorkspace.members, newMember];
    final updatedWs = state.activeWorkspace.copyWith(members: updatedMembers);
    state = state.copyWith(activeWorkspace: updatedWs);
    if (_repository.isPersistent) {
      unawaited(_repository.inviteMember(newMember));
      // Let the invited user sign in without a manual SQL insert.
      unawaited(_repository.allowlistEmail(email));
    }
  }

  void _subscribeToWorkspace(String workspaceId) {
    _workspaceSub?.cancel();
    _workspaceSub = _repository.watchWorkspace(workspaceId).listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(
        const Duration(milliseconds: 300),
        () => _reloadWorkspace(workspaceId),
      );
    });
  }

  Future<void> _reloadWorkspace(String workspaceId) async {
    final lanes = await _repository.fetchLanes(workspaceId);
    final members = await _repository.fetchMembers(workspaceId);
    final workspace = await _repository.fetchWorkspace(workspaceId);
    if (!ref.mounted || state.activeWorkspace.id != workspaceId) return;

    if (lanes != null) {
      state = state.copyWith(lanes: lanes);
    }
    if (members != null) {
      state = state.copyWith(
        activeWorkspace: state.activeWorkspace.copyWith(members: members),
      );
    }
    if (workspace != null) {
      final membersForWs = state.activeWorkspace.members;
      final updatedWs = workspace.copyWith(members: membersForWs);
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
