import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/core/repositories/activity_log_repository.dart';
import 'package:task_sphere/core/repositories/task_repository.dart';
import 'package:task_sphere/core/repositories/workspace_repository.dart';
import 'package:task_sphere/models/activity_log.dart';
import 'package:task_sphere/models/lane.dart';
import 'package:task_sphere/models/task.dart';
import 'package:task_sphere/models/workspace.dart';
import 'package:task_sphere/models/user_profile.dart';
import 'package:task_sphere/providers/auth_provider.dart';
import 'package:task_sphere/providers/demo_mode_provider.dart';
import 'package:task_sphere/providers/task_provider.dart';
import 'package:task_sphere/providers/workspace_provider.dart';

class FakeTaskRepository implements TaskRepository {
  final List<TaskItem> stored = [];
  final List<TaskItem> inserted = [];
  final List<TaskItem> updated = [];
  final List<String> deleted = [];

  @override
  bool get isPersistent => true;

  @override
  Future<List<TaskItem>?> fetchTasks(String workspaceId) async => List.of(stored);

  @override
  Future<void> insertTask(TaskItem task) async {
    inserted.add(task);
    stored.add(task);
  }

  @override
  Future<void> updateTask(TaskItem task) async {
    updated.add(task);
    final index = stored.indexWhere((t) => t.id == task.id);
    if (index != -1) stored[index] = task;
  }

  @override
  Future<void> deleteTask(String taskId) async {
    deleted.add(taskId);
    stored.removeWhere((t) => t.id == taskId);
  }

  @override
  Stream<void> watchTasks(String workspaceId) => const Stream.empty();
}

class FakeWorkspaceRepository implements WorkspaceRepository {
  List<Workspace> workspaces = [];
  List<KanbanLane> lanes = [];
  List<WorkspaceMember> members = [];
  int createCalls = 0;
  int inviteCalls = 0;
  int laneAddCalls = 0;
  int reorderCalls = 0;
  final List<String> deleteCalls = [];
  final List<String> allowlisted = [];

  @override
  bool get isPersistent => true;

  @override
  Future<WorkspacesSnapshot?> fetchWorkspaces({
    required String userId,
    required String email,
  }) async =>
      (workspaces: List.of(workspaces), lanes: List.of(lanes));

  @override
  Future<List<KanbanLane>?> fetchLanes(String workspaceId) async =>
      List.of(lanes.where((l) => l.workspaceId == workspaceId));

  @override
  Future<List<WorkspaceMember>?> fetchMembers(String workspaceId) async =>
      List.of(members.where((m) => m.workspaceId == workspaceId));

  @override
  Future<Workspace?> fetchWorkspace(String workspaceId) async {
    for (final ws in workspaces) {
      if (ws.id == workspaceId) return ws;
    }
    return null;
  }

  @override
  Future<WorkspaceSnapshot?> createWorkspace({
    required String name,
    required String adminId,
    required String adminEmail,
  }) async {
    createCalls += 1;
    final workspace = Workspace(
      id: 'ws-remote',
      name: name,
      adminId: adminId,
      members: [
        WorkspaceMember(
          id: 'm-1',
          workspaceId: 'ws-remote',
          userId: adminId,
          email: adminEmail,
          role: UserRole.admin,
        ),
      ],
    );
    workspaces = [workspace, ...workspaces];
    lanes = [
      KanbanLane(id: 'rl-1', workspaceId: 'ws-remote', title: 'To Do', orderIndex: 0, isDefault: true),
    ];
    return (workspace: workspace, lanes: List.of(lanes));
  }

  @override
  Future<void> deleteWorkspace(String workspaceId) async {
    deleteCalls.add(workspaceId);
    workspaces.removeWhere((w) => w.id == workspaceId);
  }

  @override
  Future<void> updateAutoArchiveDays(String workspaceId, int days) async {}

  @override
  Future<void> updateShowArchivedTasks(String workspaceId, bool show) async {}

  @override
  Future<void> addLane(KanbanLane lane) async {
    laneAddCalls += 1;
    lanes.add(lane);
  }

  @override
  Future<void> updateLane(KanbanLane lane) async {}

  @override
  Future<void> deleteLane(String laneId) async {}

  @override
  Future<void> reorderLanes(List<KanbanLane> orderedLanes) async {
    reorderCalls += 1;
    final byId = {for (final lane in orderedLanes) lane.id: lane.orderIndex};
    lanes = [
      for (final lane in lanes)
        lane.copyWith(orderIndex: byId[lane.id] ?? lane.orderIndex),
    ];
  }

  @override
  Future<void> inviteMember(WorkspaceMember member) async {
    inviteCalls += 1;
    members.add(member);
  }

  @override
  Future<void> allowlistEmail(String email) async {
    allowlisted.add(email.toLowerCase());
  }

  @override
  Stream<void> watchWorkspace(String workspaceId) => const Stream.empty();
}

class FakeActivityLogRepository implements ActivityLogRepository {
  final List<ActivityLog> stored = [];
  final List<ActivityLog> inserted = [];

  @override
  bool get isPersistent => true;

  @override
  Future<List<ActivityLog>?> fetchLogs(String workspaceId) async => List.of(stored);

  @override
  Future<void> insertLog(ActivityLog log) async {
    inserted.add(log);
    stored.add(log);
  }

  @override
  Stream<void> watchLogs(String workspaceId) => const Stream.empty();
}

class _FakeWorkspaceNotifier extends WorkspaceNotifier {
  _FakeWorkspaceNotifier(this.initialState);

  final WorkspaceState initialState;

  @override
  WorkspaceState build() => initialState;
}

WorkspaceState _workspaceState(Workspace workspace, List<KanbanLane> lanes) {
  return WorkspaceState(
    activeWorkspace: workspace,
    allWorkspaces: [workspace],
    lanes: lanes,
  );
}

ProviderContainer _makeContainer({
  required WorkspaceRepository workspaceRepo,
  TaskRepository? taskRepo,
  ActivityLogRepository? logRepo,
  Workspace? workspace,
  List<KanbanLane>? lanes,
}) {
  final ws = workspace ?? Workspace(id: 'ws-1', name: 'W', adminId: 'a');
  final ls = lanes ?? [KanbanLane(id: 'lane-1', workspaceId: ws.id, title: 'To Do')];
  final notifier = _FakeWorkspaceNotifier(_workspaceState(ws, ls));
  return ProviderContainer(
    overrides: [
      // A real signed-in user (not the demo sandbox user, whose mutations
      // are blocked).
      authProvider.overrideWith(
        () => _FixedAuthNotifier(
          UserProfile(id: 'a', email: 'a@x.com', displayName: 'A'),
        ),
      ),
      workspaceRepositoryProvider.overrideWith((ref) => workspaceRepo),
      if (taskRepo != null) taskRepositoryProvider.overrideWith((ref) => taskRepo),
      if (logRepo != null) activityLogRepositoryProvider.overrideWith((ref) => logRepo),
      activeWorkspaceProvider.overrideWith(() => notifier),
    ],
  );
}

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this.user);

  final UserProfile? user;

  @override
  UserProfile? build() => user;
}

ProviderContainer _workspaceContainer(WorkspaceRepository repo) {
  return ProviderContainer(
    overrides: [
      workspaceRepositoryProvider.overrideWith((ref) => repo),
      authProvider.overrideWith(
        () => _FixedAuthNotifier(
          UserProfile(id: 'a', email: 'a@x.com', displayName: 'A'),
        ),
      ),
    ],
  );
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('TaskNotifier with a persistent repository', () {
    test('loads tasks from the repository on init', () async {
      final repo = FakeTaskRepository()
        ..stored.add(TaskItem(
          id: 'remote-1',
          workspaceId: 'ws-1',
          laneId: 'lane-1',
          title: 'Remote task',
        ));
      final container = _makeContainer(workspaceRepo: FakeWorkspaceRepository(), taskRepo: repo);
      addTearDown(container.dispose);

      expect(container.read(tasksProvider), isEmpty);
      await _settle();

      expect(container.read(tasksProvider).map((t) => t.id), ['remote-1']);
    });

    test('addTask writes to the repository', () async {
      final repo = FakeTaskRepository();
      final container = _makeContainer(workspaceRepo: FakeWorkspaceRepository(), taskRepo: repo);
      addTearDown(container.dispose);

      final task = TaskItem(id: 't-1', workspaceId: 'ws-1', laneId: 'lane-1', title: 'New');
      container.read(tasksProvider.notifier).addTask(task);
      await _settle();

      expect(repo.inserted.map((t) => t.id), ['t-1']);
      expect(container.read(tasksProvider).first.id, 't-1');
    });

    test('moveTaskLane persists the lane change', () async {
      final repo = FakeTaskRepository()
        ..stored.add(TaskItem(id: 't-1', workspaceId: 'ws-1', laneId: 'lane-1', title: 'Task'));
      final container = _makeContainer(
        workspaceRepo: FakeWorkspaceRepository(),
        taskRepo: repo,
        lanes: [
          KanbanLane(id: 'lane-1', workspaceId: 'ws-1', title: 'To Do'),
          KanbanLane(id: 'lane-2', workspaceId: 'ws-1', title: 'Done'),
        ],
      );
      addTearDown(container.dispose);
      container.read(tasksProvider);
      await _settle();

      container.read(tasksProvider.notifier).moveTaskLane('t-1', 'lane-2');
      await _settle();

      expect(repo.updated.single.laneId, 'lane-2');
      expect(container.read(tasksProvider).single.laneId, 'lane-2');
    });

    test('deleteTask removes it from the repository', () async {
      final repo = FakeTaskRepository()
        ..stored.add(TaskItem(id: 't-1', workspaceId: 'ws-1', laneId: 'lane-1', title: 'Task'));
      final container = _makeContainer(workspaceRepo: FakeWorkspaceRepository(), taskRepo: repo);
      addTearDown(container.dispose);
      await _settle();

      container.read(tasksProvider.notifier).deleteTask('t-1');
      await _settle();

      expect(repo.deleted, ['t-1']);
      expect(container.read(tasksProvider), isEmpty);
    });
  });

  group('WorkspaceNotifier with a persistent repository', () {
    test('loadInitialData populates state from the repository', () async {
      final repo = FakeWorkspaceRepository()
        ..workspaces = [
          Workspace(
            id: 'ws-1',
            name: 'Team',
            adminId: 'a',
            members: [
              WorkspaceMember(id: 'm-1', workspaceId: 'ws-1', email: 'a@x.com', role: UserRole.admin),
            ],
          ),
        ]
        ..lanes = [KanbanLane(id: 'lane-1', workspaceId: 'ws-1', title: 'To Do')];

      final container = _workspaceContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(activeWorkspaceProvider.notifier);

      await notifier.loadInitialData();

      expect(notifier.state.activeWorkspace.id, 'ws-1');
      expect(notifier.state.activeWorkspace.members.single.email, 'a@x.com');
      expect(notifier.state.lanes.single.title, 'To Do');
      expect(notifier.state.isLoading, isFalse);
    });

    test('loadInitialData seeds the five default lanes when the workspace has none', () async {
      final repo = FakeWorkspaceRepository()
        ..workspaces = [Workspace(id: 'ws-1', name: 'Team', adminId: 'a')];
      final container = _workspaceContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(activeWorkspaceProvider.notifier);

      // build() fires loadInitialData() unawaited; let that settle.
      await _settle();

      expect(repo.laneAddCalls, 5);
      expect(notifier.state.lanes.map((l) => l.title).toList(),
          ['To Do', 'In Progress', 'Partially Done', 'Done', 'Wont Do']);
      for (var i = 0; i < notifier.state.lanes.length; i++) {
        expect(notifier.state.lanes[i].orderIndex, i);
        expect(notifier.state.lanes[i].isDefault, isTrue);
      }
    });

    test('loadInitialData keeps existing lanes without re-seeding', () async {
      final repo = FakeWorkspaceRepository()
        ..workspaces = [Workspace(id: 'ws-1', name: 'Team', adminId: 'a')]
        ..lanes = [KanbanLane(id: 'lane-1', workspaceId: 'ws-1', title: 'To Do')];
      final container = _workspaceContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(activeWorkspaceProvider.notifier);

      await notifier.loadInitialData();

      expect(repo.laneAddCalls, 0);
      expect(notifier.state.lanes.single.title, 'To Do');
    });

    test('loadInitialData shows the no-workspace state when the user has no workspaces', () async {
      final repo = FakeWorkspaceRepository();
      final container = _workspaceContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(activeWorkspaceProvider.notifier);

      await notifier.loadInitialData();

      expect(notifier.state.hasWorkspace, isFalse);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.activeWorkspace.name, 'No Workspace');
    });

    test('createWorkspace uses the repository snapshot', () async {
      final repo = FakeWorkspaceRepository();
      final container = _workspaceContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(activeWorkspaceProvider.notifier);

      await notifier.createWorkspace('Remote Team', 'a', 'a@x.com');

      expect(repo.createCalls, 1);
      expect(notifier.state.activeWorkspace.id, 'ws-remote');
      expect(notifier.state.activeWorkspace.name, 'Remote Team');
      expect(notifier.state.lanes.single.id, 'rl-1');
    });

    test('inviteMember persists to the repository', () async {
      final repo = FakeWorkspaceRepository();
      final container = _workspaceContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(activeWorkspaceProvider.notifier);
      await notifier.createWorkspace('Team', 'a', 'a@x.com');

      notifier.inviteMember('New@X.com', UserRole.member);
      await _settle();

      expect(repo.inviteCalls, 1);
      expect(
        notifier.state.activeWorkspace.members.any((m) => m.email == 'New@X.com'),
        isTrue,
      );
      expect(repo.allowlisted, ['new@x.com']);
    });

    test('addLane persists only the new lane without reindexing', () async {
      final repo = FakeWorkspaceRepository();
      final container = _workspaceContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(activeWorkspaceProvider.notifier);
      await notifier.createWorkspace('Team', 'a', 'a@x.com');

      await notifier.addLane('In Review', const Color(0xFFEC4899));

      expect(repo.laneAddCalls, 1);
      // New lanes are appended at the bottom of the board; adding a lane
      // never rewrites the order of existing lanes.
      expect(repo.reorderCalls, 0);
      expect(notifier.state.lanes.last.title, 'In Review');
      expect(notifier.state.lanes.first.title, 'To Do');
    });

    test('dragging a lane is the only action that reindexes the board', () async {
      final repo = FakeWorkspaceRepository();
      final container = _workspaceContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(activeWorkspaceProvider.notifier);
      await notifier.createWorkspace('Team', 'a', 'a@x.com');
      await notifier.addLane('In Review', const Color(0xFFEC4899));

      notifier.reorderLanes(0, 1);
      await _settle();

      expect(repo.reorderCalls, 1);
      // Reindexing rewrites the order_index of the affected lanes.
      expect(repo.lanes.map((l) => l.orderIndex).toList(), [1, 0]);
      expect(notifier.state.lanes.map((l) => l.title).toList(), [
        'In Review',
        'To Do',
      ]);
    });
  });

  group('ActivityLogNotifier with a persistent repository', () {
    test('loads logs from the repository on init', () async {
      final repo = FakeActivityLogRepository()
        ..stored.add(ActivityLog(id: 'log-1', workspaceId: 'ws-1', userName: 'A', action: 'x'));
      final container = _makeContainer(workspaceRepo: FakeWorkspaceRepository(), logRepo: repo);
      addTearDown(container.dispose);
      container.read(activityLogsProvider);
      await _settle();

      expect(container.read(activityLogsProvider).single.id, 'log-1');
    });

    test('addLog prepends locally and persists', () async {
      final repo = FakeActivityLogRepository();
      final container = _makeContainer(workspaceRepo: FakeWorkspaceRepository(), logRepo: repo);
      addTearDown(container.dispose);

      container
          .read(activityLogsProvider.notifier)
          .addLog('ws-1', 'Alex', 'Created task', taskId: 't-1');
      await _settle();

      expect(repo.inserted.single.action, 'Created task');
      expect(container.read(activityLogsProvider).first.action, 'Created task');
    });
  });

  group('Demo sandbox guards', () {
    final workspace = Workspace(id: 'ws-1', name: 'W', adminId: 'a');
    final lanes = [KanbanLane(id: 'lane-1', workspaceId: 'ws-1', title: 'To Do')];

    test('addTask is a no-op for the demo user', () async {
      final repo = FakeTaskRepository();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FixedAuthNotifier(UserProfile.demo())),
          workspaceRepositoryProvider.overrideWith((ref) => FakeWorkspaceRepository()),
          taskRepositoryProvider.overrideWith((ref) => repo),
          activeWorkspaceProvider.overrideWith(
            () => _FakeWorkspaceNotifier(_workspaceState(workspace, lanes)),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(tasksProvider);
      await _settle();

      container.read(tasksProvider.notifier).addTask(
            TaskItem(id: 't-1', workspaceId: 'ws-1', laneId: 'lane-1', title: 'New'),
          );
      await _settle();

      expect(container.read(tasksProvider), isEmpty);
      expect(repo.inserted, isEmpty);
    });

    test('createWorkspace and inviteMember are no-ops for the demo user', () async {
      final repo = FakeWorkspaceRepository();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FixedAuthNotifier(UserProfile.demo())),
          workspaceRepositoryProvider.overrideWith((ref) => repo),
          activeWorkspaceProvider.overrideWith(
            () => _FakeWorkspaceNotifier(_workspaceState(workspace, lanes)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(activeWorkspaceProvider.notifier);

      await notifier.createWorkspace('Team', 'a', 'a@x.com');

      expect(notifier.state.activeWorkspace.id, 'ws-1');
      expect(repo.createCalls, 0);

      notifier.inviteMember('new@x.com', UserRole.member);
      await _settle();

      expect(notifier.state.activeWorkspace.members, isEmpty);
      expect(repo.inviteCalls, 0);
    });

    test('demo mode starts logged out so the login page shows', () {
      final container = ProviderContainer(
        overrides: [demoModeProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      expect(container.read(authProvider), isNull);
    });

    test('isDemoUserProvider flags only the demo user', () {
      final demoContainer = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _FixedAuthNotifier(UserProfile.demo()))],
      );
      addTearDown(demoContainer.dispose);
      expect(demoContainer.read(isDemoUserProvider), isTrue);

      final realContainer = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(UserProfile(id: 'u-1', email: 'u@x.com', displayName: 'U')),
          ),
        ],
      );
      addTearDown(realContainer.dispose);
      expect(realContainer.read(isDemoUserProvider), isFalse);
    });

    test('addLane and updateLane ignore empty titles', () {
      final container = _makeContainer(workspaceRepo: FakeWorkspaceRepository());
      addTearDown(container.dispose);
      final notifier = container.read(activeWorkspaceProvider.notifier);

      notifier.addLane('   ', const Color(0xFFEC4899));

      expect(notifier.state.lanes, hasLength(1));

      notifier.updateLane('lane-1', '  ', const Color(0xFF3B82F6));

      expect(notifier.state.lanes.single.title, 'To Do');
    });
  });

  group('Workspace deletion', () {
    Workspace adminWorkspace({String id = 'ws-1', String name = 'Team'}) {
      return Workspace(
        id: id,
        name: name,
        adminId: 'a',
        members: [
          WorkspaceMember(
            id: 'm-1',
            workspaceId: id,
            userId: 'a',
            email: 'a@x.com',
            role: UserRole.admin,
          ),
        ],
      );
    }

    // Uses the real notifier (build() wires the repository) with the
    // authenticated admin user from _workspaceContainer.
    Future<WorkspaceNotifier> loadFromRepo(FakeWorkspaceRepository repo) async {
      final container = _workspaceContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(activeWorkspaceProvider.notifier);
      await notifier.loadInitialData();
      return notifier;
    }

    test('admin deleting the active workspace switches to the next one', () async {
      final ws1 = adminWorkspace();
      final ws2 = Workspace(id: 'ws-2', name: 'Other', adminId: 'a');
      final repo = FakeWorkspaceRepository()..workspaces = [ws1, ws2];
      final notifier = await loadFromRepo(repo);

      await notifier.deleteWorkspace('ws-1');

      expect(repo.deleteCalls, ['ws-1']);
      expect(notifier.state.activeWorkspace.id, 'ws-2');
      expect(notifier.state.allWorkspaces, hasLength(1));
      expect(notifier.state.isLoading, isFalse);
    });

    test('deleting the last workspace shows the no-workspace state', () async {
      final ws1 = adminWorkspace();
      final repo = FakeWorkspaceRepository()..workspaces = [ws1];
      final notifier = await loadFromRepo(repo);

      await notifier.deleteWorkspace('ws-1');

      expect(repo.deleteCalls, ['ws-1']);
      expect(notifier.state.hasWorkspace, isFalse);
      expect(notifier.state.activeWorkspace.name, 'No Workspace');
    });

    test('non-admins cannot delete the workspace', () async {
      final ws1 = Workspace(
        id: 'ws-1',
        name: 'Team',
        adminId: 'someone-else',
        members: [
          WorkspaceMember(
            id: 'm-1',
            workspaceId: 'ws-1',
            userId: 'a',
            email: 'a@x.com',
            role: UserRole.member,
          ),
        ],
      );
      final repo = FakeWorkspaceRepository()..workspaces = [ws1];
      final notifier = await loadFromRepo(repo);

      await notifier.deleteWorkspace('ws-1');

      expect(repo.deleteCalls, isEmpty);
      expect(notifier.state.activeWorkspace.id, 'ws-1');
    });

    test('demo user cannot delete the workspace even as its admin', () async {
      final ws1 = Workspace(
        id: 'ws-1',
        name: 'Team',
        adminId: 'demo-user-123',
        members: [
          WorkspaceMember(
            id: 'm-1',
            workspaceId: 'ws-1',
            userId: 'demo-user-123',
            email: 'alex.admin@tasksphere.app',
            role: UserRole.admin,
          ),
        ],
      );
      final repo = FakeWorkspaceRepository()..workspaces = [ws1];
      final container = ProviderContainer(
        overrides: [
          workspaceRepositoryProvider.overrideWith((ref) => repo),
          authProvider.overrideWith(() => _FixedAuthNotifier(UserProfile.demo())),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(activeWorkspaceProvider.notifier);
      // Let build()'s unawaited loadInitialData() finish loading ws-1.
      await _settle();

      await notifier.deleteWorkspace('ws-1');

      expect(repo.deleteCalls, isEmpty);
      expect(notifier.state.activeWorkspace.id, 'ws-1');
    });
  });
}
