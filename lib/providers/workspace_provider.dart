import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// Whether the signed-in user may create a workspace (site admin, or
/// allowlisted and not a plain member anywhere). Drives the create entry
/// points in the UI; the provider and database enforce the same rule.
final canCreateWorkspaceProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(isDemoUserProvider)) return false;
  return ref.watch(workspaceRepositoryProvider).canCreateWorkspace();
});

class WorkspaceState {
  final Workspace activeWorkspace;
  final List<Workspace> allWorkspaces;
  final List<KanbanLane> lanes;
  final bool isLoading;

  /// The workspace the signed-in user was just removed from (realtime kick).
  /// The navigation shell shows one notice, then calls
  /// [WorkspaceNotifier.clearRemovedFromWorkspace].
  final String? removedFromWorkspace;

  WorkspaceState({
    required this.activeWorkspace,
    required this.allWorkspaces,
    required this.lanes,
    this.isLoading = false,
    this.removedFromWorkspace,
  });

  // Sentinel so copyWith can clear removedFromWorkspace with an explicit
  // null; a plain `?? this.x` would make the notice impossible to dismiss.
  static const Object _unset = Object();

  WorkspaceState copyWith({
    Workspace? activeWorkspace,
    List<Workspace>? allWorkspaces,
    List<KanbanLane>? lanes,
    bool? isLoading,
    Object? removedFromWorkspace = _unset,
  }) {
    return WorkspaceState(
      activeWorkspace: activeWorkspace ?? this.activeWorkspace,
      allWorkspaces: allWorkspaces ?? this.allWorkspaces,
      lanes: lanes ?? this.lanes,
      isLoading: isLoading ?? this.isLoading,
      removedFromWorkspace: removedFromWorkspace == _unset
          ? this.removedFromWorkspace
          : removedFromWorkspace as String?,
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
  static WorkspaceState empty({String? removedFromWorkspace}) {
    return WorkspaceState(
      activeWorkspace: Workspace(id: '', name: 'No Workspace', adminId: ''),
      allWorkspaces: const [],
      lanes: const [],
      removedFromWorkspace: removedFromWorkspace,
    );
  }
}

class WorkspaceNotifier extends Notifier<WorkspaceState> {
  WorkspaceRepository? _repo;
  String? _userId;
  String? _userEmail;

  StreamSubscription<void>? _workspaceSub;
  StreamSubscription<void>? _membershipSub;
  Timer? _reloadDebounce;
  Timer? _membershipDebounce;

  /// Number of lane writes in flight. Realtime reloads are suppressed while
  /// this is non-zero so a reload can never snapshot the database mid-write
  /// and clobber the state with a half-written lane order.
  int _laneWritesInFlight = 0;

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

  /// Local persistence key for the active workspace, scoped to the signed-in
  /// user so different accounts on one device remember their own board.
  String? get _activeWorkspaceKey {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return null;
    return 'active_workspace_id_$userId';
  }

  Future<void> _persistActiveWorkspace(String workspaceId) async {
    final key = _activeWorkspaceKey;
    if (key == null || !_repository.isPersistent) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, workspaceId);
  }

  @override
  WorkspaceState build() {
    _repo = ref.watch(workspaceRepositoryProvider);
    final user = ref.read(authProvider);
    _userId = user?.id;
    _userEmail = user?.email;

    ref.onDispose(() {
      _workspaceSub?.cancel();
      _membershipSub?.cancel();
      _reloadDebounce?.cancel();
      _membershipDebounce?.cancel();
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
      autoExpiryLaneIds: const ['lane-4', 'lane-5'],
      members: [
        WorkspaceMember(
          id: 'mem-1',
          workspaceId: demoWorkspaceId,
          userId: 'demo-user-123',
          email: 'alex.admin@tasksphere.app',
          role: UserRole.admin,
          // Match the demo tasks' assigneeName values so cards keep their
          // names when members start carrying display names.
          displayName: 'Alex Morgan',
        ),
        WorkspaceMember(
          id: 'mem-2',
          workspaceId: demoWorkspaceId,
          userId: 'user-456',
          email: 'sarah.designer@tasksphere.app',
          role: UserRole.member,
          displayName: 'Sarah Designer',
        ),
        WorkspaceMember(
          id: 'mem-3',
          workspaceId: demoWorkspaceId,
          userId: 'user-789',
          email: 'dev.team@tasksphere.app',
          role: UserRole.member,
          displayName: 'Dev Team',
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

    // Reopen the board the user was last on; a stale stored id (deleted or
    // left workspace) falls back to the first workspace.
    String? storedId;
    final key = _activeWorkspaceKey;
    if (key != null) {
      final prefs = await SharedPreferences.getInstance();
      storedId = prefs.getString(key);
    }
    if (!ref.mounted) return;

    final active = snapshot.workspaces.firstWhere(
      (w) => w.id == storedId,
      orElse: () => snapshot.workspaces.first,
    );
    final lanes = await _ensureLanes(active.id);
    if (!ref.mounted) return;
    final sortedLanes = List<KanbanLane>.from(lanes)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    state = WorkspaceState(
      activeWorkspace: active,
      allWorkspaces: snapshot.workspaces,
      lanes: sortedLanes,
      isLoading: false,
    );
    _subscribeToWorkspace(active.id);
    _subscribeToMemberships();
  }

  /// Watches the signed-in user's memberships across ALL workspaces, so an
  /// invite to another workspace or a removal shows up without a refresh.
  /// Subscriptions are per user, so unlike the active-workspace channel this
  /// is set up once per session, not on every switch.
  void _subscribeToMemberships() {
    final userId = _userId;
    if (!_repository.isPersistent || userId == null || userId.isEmpty) return;
    _membershipSub?.cancel();
    _membershipSub = _repository.watchMemberships(userId).listen((_) {
      _membershipDebounce?.cancel();
      _membershipDebounce = Timer(
        const Duration(milliseconds: 300),
        _reloadMemberships,
      );
    });
  }

  /// Re-fetches the user's workspace list after a membership change. When the
  /// active workspace is no longer among them (kicked out, or it was deleted
  /// and the membership cascade fired), switch to the first remaining
  /// workspace — or the empty state — and record the removal for a notice.
  Future<void> _reloadMemberships() async {
    final userId = _userId;
    final userEmail = _userEmail;
    if (userId == null || userEmail == null) return;
    final snapshot =
        await _repository.fetchWorkspaces(userId: userId, email: userEmail);
    if (!ref.mounted || snapshot == null) return;

    final currentActiveId = state.activeWorkspace.id;
    if (snapshot.workspaces.any((w) => w.id == currentActiveId)) {
      // Still a member: the switcher list may have grown (invite to a new
      // workspace) or been renamed; the active workspace's live data keeps
      // coming from its own channel.
      state = state.copyWith(allWorkspaces: snapshot.workspaces);
      return;
    }

    final removedName = state.activeWorkspace.name;
    if (snapshot.workspaces.isEmpty) {
      // No workspaces left: the existing empty state screen guides the user.
      state = WorkspaceState.empty(removedFromWorkspace: removedName);
      return;
    }

    final next = snapshot.workspaces.first;
    if (_repository.isPersistent) {
      final lanes = await _ensureLanes(next.id);
      if (!ref.mounted || state.activeWorkspace.id != currentActiveId) return;
      state = WorkspaceState(
        activeWorkspace: next,
        allWorkspaces: snapshot.workspaces,
        lanes: lanes,
        isLoading: false,
        removedFromWorkspace: removedName,
      );
      _subscribeToWorkspace(next.id);
      unawaited(_persistActiveWorkspace(next.id));
    }
  }

  /// Called by the UI after it has shown the removal notice.
  void clearRemovedFromWorkspace() {
    if (state.removedFromWorkspace == null) return;
    state = state.copyWith(removedFromWorkspace: null);
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
    return List<KanbanLane>.from(lanes)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  Future<void> createWorkspace(String name, String adminId, String adminEmail) async {
    // The demo sandbox cannot create workspaces; the UI hides the entry point.
    if (ref.read(isDemoUserProvider)) return;
    final repo = _repository;
    if (repo.isPersistent) {
      // Mirrors can_create_workspace(): the site admin, or allowlisted users
      // who are not plain members anywhere, may create workspaces.
      final canCreate = await repo.canCreateWorkspace();
      if (!canCreate || !ref.mounted) return;
    } else if (state.allWorkspaces.isNotEmpty &&
        !isAdmin(ref.read(authProvider))) {
      // In-memory fallback: only admins may create additional workspaces.
      return;
    }
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
      unawaited(_persistActiveWorkspace(created.workspace.id));
      return;
    }

    final wsId = _uuid.v4();
    // The workspace references the lane ids for its default auto-expiry
    // selection, so the lanes are created first.
    final newLanes = [
      KanbanLane(id: _uuid.v4(), workspaceId: wsId, title: 'To Do', colorHex: '#3B82F6', orderIndex: 0, isDefault: true),
      KanbanLane(id: _uuid.v4(), workspaceId: wsId, title: 'In Progress', colorHex: '#F59E0B', orderIndex: 1, isDefault: true),
      KanbanLane(id: _uuid.v4(), workspaceId: wsId, title: 'Partially Done', colorHex: '#8B5CF6', orderIndex: 2, isDefault: true),
      KanbanLane(id: _uuid.v4(), workspaceId: wsId, title: 'Done', colorHex: '#10B981', orderIndex: 3, isDefault: true),
      KanbanLane(id: _uuid.v4(), workspaceId: wsId, title: 'Wont Do', colorHex: '#EF4444', orderIndex: 4, isDefault: true),
    ];
    final newWs = Workspace(
      id: wsId,
      name: name,
      adminId: adminId,
      autoExpiryLaneIds: [
        for (final lane in newLanes)
          if (lane.title == 'Done' || lane.title == 'Wont Do') lane.id,
      ],
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
      unawaited(_persistActiveWorkspace(next.id));
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
    unawaited(_persistActiveWorkspace(ws.id));
  }

  // --- Admin Lane Customization ---
  Future<void> addLane(String title, Color color) async {
    if (!isAdmin(ref.read(authProvider))) return;
    if (title.trim().isEmpty) return;
    final hex = '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    // New lanes go to the bottom: one past the highest existing index, so no
    // other lane's order changes. Only a drag reorder rewrites order_index.
    final maxIndex = state.lanes.isEmpty
        ? -1
        : state.lanes
            .map((l) => l.orderIndex)
            .reduce((max, val) => val > max ? val : max);
    final newLane = KanbanLane(
      id: _uuid.v4(),
      workspaceId: state.activeWorkspace.id,
      title: title,
      colorHex: hex,
      orderIndex: maxIndex + 1,
      isDefault: false,
    );

    final updatedLanes = [...state.lanes, newLane]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    state = state.copyWith(lanes: updatedLanes);
    _lanesByWorkspace[state.activeWorkspace.id] = List.of(state.lanes);
    final repo = _repository;
    if (!repo.isPersistent) return;

    // Persist only the new lane; the realtime reload reconciles the order.
    _laneWritesInFlight++;
    try {
      await repo.addLane(newLane);
    } finally {
      _laneWritesInFlight--;
    }
  }

  void updateLane(String laneId, String newTitle, Color newColor) {
    if (!isAdmin(ref.read(authProvider))) return;
    if (newTitle.trim().isEmpty) return;
    final hex = '#${newColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    KanbanLane? updated;
    final updatedLanes = state.lanes.map((l) {
      if (l.id == laneId) {
        updated = l.copyWith(title: newTitle, colorHex: hex);
        return updated!;
      }
      return l;
    }).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    state = state.copyWith(lanes: updatedLanes);
    _lanesByWorkspace[state.activeWorkspace.id] = List.of(state.lanes);
    if (_repository.isPersistent && updated != null) {
      unawaited(_repository.updateLane(updated!));
    }
  }

  void reorderLanes(int oldIndex, int newIndex) {
    if (!isAdmin(ref.read(authProvider))) return;
    final list = List<KanbanLane>.from(state.lanes);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    final reindexed = list.asMap().entries.map((entry) {
      return entry.value.copyWith(orderIndex: entry.key);
    }).toList();

    state = state.copyWith(lanes: reindexed);
    _lanesByWorkspace[state.activeWorkspace.id] = List.of(state.lanes);
    if (_repository.isPersistent) {
      _laneWritesInFlight++;
      unawaited(
        _repository
            .reorderLanes(reindexed)
            .whenComplete(() => _laneWritesInFlight--),
      );
    }
  }

  void deleteLane(String laneId) {
    if (!isAdmin(ref.read(authProvider))) return;
    final updatedLanes = state.lanes.where((l) => l.id != laneId).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    state = state.copyWith(lanes: updatedLanes);
    _lanesByWorkspace[state.activeWorkspace.id] = List.of(state.lanes);
    if (_repository.isPersistent) {
      _laneWritesInFlight++;
      unawaited(
        _repository
            .deleteLane(laneId)
            .whenComplete(() => _laneWritesInFlight--),
      );
    }
  }

  // --- Workspace Settings ---
  void updateAutoArchiveThreshold(int days) {
    if (!isAdmin(ref.read(authProvider))) return;
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
    if (!isAdmin(ref.read(authProvider))) return;
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

  /// Renames the active workspace. Admin-only and read-only in the demo
  /// sandbox, mirroring the other workspace settings mutations.
  void updateWorkspaceName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (ref.read(isDemoUserProvider)) return;
    if (!isAdmin(ref.read(authProvider))) return;
    if (trimmed == state.activeWorkspace.name) return;
    final updatedWs = state.activeWorkspace.copyWith(name: trimmed);
    state = state.copyWith(
      activeWorkspace: updatedWs,
      allWorkspaces: [
        for (final w in state.allWorkspaces)
          w.id == updatedWs.id ? updatedWs : w,
      ],
    );
    if (_repository.isPersistent) {
      unawaited(_repository.updateWorkspaceName(updatedWs.id, trimmed));
    }
  }

  void updateAutoExpiryLanes(List<String> laneIds) {
    if (!isAdmin(ref.read(authProvider))) return;
    final updatedWs = state.activeWorkspace.copyWith(autoExpiryLaneIds: laneIds);
    state = state.copyWith(
      activeWorkspace: updatedWs,
      allWorkspaces: [
        for (final w in state.allWorkspaces)
          w.id == updatedWs.id ? updatedWs : w,
      ],
    );
    if (_repository.isPersistent) {
      unawaited(_repository.updateAutoExpiryLaneIds(updatedWs.id, laneIds));
    }
  }

  void inviteMember(String email, UserRole role) {
    // The demo sandbox cannot invite members; the UI hides the entry point.
    if (ref.read(isDemoUserProvider)) return;
    if (!isAdmin(ref.read(authProvider))) return;
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

  /// Admins can give members a friendly display name shown instead of the
  /// email prefix; an empty value reverts to the email fallback.
  void updateMemberDisplayName(String memberId, String? displayName) {
    if (ref.read(isDemoUserProvider)) return;
    if (!isAdmin(ref.read(authProvider))) return;
    final trimmed = displayName?.trim();
    final effective = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    final updatedMembers = [
      for (final m in state.activeWorkspace.members)
        if (m.id == memberId)
          WorkspaceMember(
            id: m.id,
            workspaceId: m.workspaceId,
            userId: m.userId,
            email: m.email,
            role: m.role,
            displayName: effective,
          )
        else
          m,
    ];
    final updatedWs = state.activeWorkspace.copyWith(members: updatedMembers);
    state = state.copyWith(
      activeWorkspace: updatedWs,
      allWorkspaces: [
        for (final w in state.allWorkspaces)
          w.id == updatedWs.id ? updatedWs : w,
      ],
    );
    WorkspaceMember? updated;
    for (final m in updatedMembers) {
      if (m.id == memberId) updated = m;
    }
    if (_repository.isPersistent && updated != null) {
      unawaited(_repository.updateMemberDisplayName(updated));
    }
  }

  /// Removes a member — any role, other admins included — from the active
  /// workspace. Admin-only and read-only in the demo sandbox. The removed
  /// user's other devices pick up the DELETE through their membership
  /// realtime channel and are switched out of the workspace automatically.
  /// A workspace always keeps its admin who is acting (no self-removal) and
  /// its last admin.
  void removeMember(WorkspaceMember member) {
    if (ref.read(isDemoUserProvider)) return;
    if (!isAdmin(ref.read(authProvider))) return;
    final currentUser = ref.read(authProvider);
    final userEmail = currentUser?.email;
    final isSelf =
        (member.userId != null && member.userId == currentUser?.id) ||
            (userEmail != null && member.email.toLowerCase() == userEmail.toLowerCase());
    if (isSelf) return;

    final members = state.activeWorkspace.members;
    if (!members.any((m) => m.id == member.id)) return;
    final admins = members.where((m) => m.role == UserRole.admin).toList();
    // Removing the last admin would orphan the workspace.
    if (member.role == UserRole.admin && admins.length <= 1) return;

    final remaining = [
      for (final m in members)
        if (m.id != member.id) m,
    ];
    final updatedWs = state.activeWorkspace.copyWith(members: remaining);
    state = state.copyWith(
      activeWorkspace: updatedWs,
      allWorkspaces: [
        for (final w in state.allWorkspaces)
          w.id == updatedWs.id ? updatedWs : w,
      ],
    );
    if (_repository.isPersistent) {
      unawaited(_repository.removeMember(updatedWs.id, member.id));
    }
  }

  void _subscribeToWorkspace(String workspaceId) {
    _workspaceSub?.cancel();
    _workspaceSub = _repository.watchWorkspace(workspaceId).listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(
        const Duration(milliseconds: 300),
        () {
          if (_laneWritesInFlight > 0) {
            _reloadDebounce = Timer(
              const Duration(milliseconds: 300),
              () => _reloadWorkspace(workspaceId),
            );
          } else {
            _reloadWorkspace(workspaceId);
          }
        },
      );
    });
  }

  Future<void> _reloadWorkspace(String workspaceId) async {
    final lanes = await _repository.fetchLanes(workspaceId);
    final members = await _repository.fetchMembers(workspaceId);
    final workspace = await _repository.fetchWorkspace(workspaceId);
    if (!ref.mounted || state.activeWorkspace.id != workspaceId) return;

    if (lanes != null) {
      final sortedLanes = List<KanbanLane>.from(lanes)
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      state = state.copyWith(lanes: sortedLanes);
      _lanesByWorkspace[workspaceId] = sortedLanes;
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
