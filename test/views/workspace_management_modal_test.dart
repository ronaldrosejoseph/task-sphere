import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/core/repositories/workspace_repository.dart';
import 'package:task_sphere/models/lane.dart';
import 'package:task_sphere/models/user_profile.dart';
import 'package:task_sphere/models/workspace.dart';
import 'package:task_sphere/providers/auth_provider.dart';
import 'package:task_sphere/providers/workspace_provider.dart';
import 'package:task_sphere/views/workspace/workspace_management_modal.dart';
import '../providers/repository_provider_test.dart' show FakeWorkspaceRepository;

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this.user);

  final UserProfile? user;

  @override
  UserProfile? build() => user;
}

class _FakeWorkspaceNotifier extends WorkspaceNotifier {
  _FakeWorkspaceNotifier(this.initialState);

  final WorkspaceState initialState;

  @override
  WorkspaceState build() => initialState;
}

WorkspaceState _state() {
  final ws = Workspace(
    id: 'ws-1',
    name: 'Team',
    adminId: 'a',
    members: [
      WorkspaceMember(
        id: 'm-1',
        workspaceId: 'ws-1',
        userId: 'u-1',
        email: 'u@x.com',
        role: UserRole.admin,
      ),
    ],
  );
  return WorkspaceState(
    activeWorkspace: ws,
    allWorkspaces: [ws],
    lanes: [KanbanLane(id: 'lane-1', workspaceId: 'ws-1', title: 'To Do')],
  );
}

Future<void> _pumpModal(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: Center(child: WorkspaceManagementModal()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // The delete flow drives the real WorkspaceNotifier, whose build()
    // reads the stored active workspace from SharedPreferences.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('real users see the create and invite sections', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'u-1', email: 'u@x.com', displayName: 'U'),
          ),
        ),
        activeWorkspaceProvider.overrideWith(() => _FakeWorkspaceNotifier(_state())),
      ],
    );
    addTearDown(container.dispose);
    await _pumpModal(tester, container);

    expect(find.text('Switch Workspace'), findsOneWidget);
    expect(find.text('New workspace name...'), findsOneWidget);
    expect(find.text('Invite Member to Workspace'), findsOneWidget);
    expect(find.text('Current Members'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on mobile the invite email field spans the width and controls sit below', (tester) async {
    // Regression: the invite row used to squeeze the email field and could
    // overflow on narrow screens.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'u-1', email: 'u@x.com', displayName: 'U'),
          ),
        ),
        activeWorkspaceProvider.overrideWith(() => _FakeWorkspaceNotifier(_state())),
      ],
    );
    addTearDown(container.dispose);
    await _pumpModal(tester, container);

    expect(find.text('Invite Member to Workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final emailField = find.ancestor(
      of: find.text('Member Google email...'),
      matching: find.byType(TextField),
    );
    expect(emailField, findsOneWidget);
    // Full-width email entry point on a phone.
    expect(tester.getSize(emailField).width, greaterThan(200));

    // Role dropdown and Invite button are below the email field, not beside it.
    final emailBottom = tester.getBottomLeft(emailField).dy;
    expect(tester.getTopLeft(find.byType(DropdownButton<UserRole>)).dy, greaterThan(emailBottom));
    expect(
      tester.getTopLeft(find.widgetWithText(ElevatedButton, 'Invite')).dy,
      greaterThan(emailBottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('user with no workspace can still create their first one', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'u-1', email: 'u@x.com', displayName: 'U'),
          ),
        ),
        activeWorkspaceProvider.overrideWith(
          () => _FakeWorkspaceNotifier(WorkspaceState.empty()),
        ),
      ],
    );
    addTearDown(container.dispose);
    await _pumpModal(tester, container);

    expect(find.text('New workspace name...'), findsOneWidget);
    expect(find.text('Invite Member to Workspace'), findsNothing);
    expect(find.text('Delete Workspace'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo user sees no create or invite sections', (tester) async {
    // Default providers sign in the demo user (no Supabase client in tests).
    final container = ProviderContainer(
      overrides: [
        activeWorkspaceProvider.overrideWith(() => _FakeWorkspaceNotifier(_state())),
      ],
    );
    addTearDown(container.dispose);
    await _pumpModal(tester, container);

    expect(find.text('Switch Workspace'), findsOneWidget);
    expect(find.text('Current Members'), findsOneWidget);
    expect(find.text('New workspace name...'), findsNothing);
    expect(find.text('Invite Member to Workspace'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin edits a member display name from the member list', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The real notifier (no activeWorkspaceProvider override) serves the demo
    // workspace in memory; the auth override makes this user its admin while
    // bypassing the demo sandbox guards.
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'demo-user-123', email: 'alex.admin@tasksphere.app', displayName: 'Alex'),
          ),
        ),
        isDemoUserProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);
    await _pumpModal(tester, container);

    final editButtons = find.byIcon(Icons.edit_outlined);
    expect(editButtons, findsNWidgets(3));

    await tester.tap(editButtons.first);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Display name for alex.admin@tasksphere.app'),
      findsOneWidget,
    );

    // The display-name field is the dialog's only text entry.
    await tester.enterText(find.byType(TextField).last, 'Alex the Admin');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final member = container
        .read(activeWorkspaceProvider)
        .activeWorkspace
        .members
        .firstWhere((m) => m.email == 'alex.admin@tasksphere.app');
    expect(member.displayName, 'Alex the Admin');
    expect(find.text('Alex the Admin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Pushes the modal on a real dialog route (as the app does) so the
  // delete flow can pop it. Default providers give the demo workspace with
  // the demo admin user.
  Future<void> pumpPushedModal(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => showDialog(
                    context: ctx,
                    builder: (_) => const WorkspaceManagementModal(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('admin must type the workspace name to delete it', (tester) async {
    final adminWs = Workspace(
      id: 'ws-1',
      name: 'Team',
      adminId: 'u-1',
      members: [
        WorkspaceMember(
          id: 'm-1',
          workspaceId: 'ws-1',
          userId: 'u-1',
          email: 'u@x.com',
          role: UserRole.admin,
        ),
      ],
    );
    final repo = FakeWorkspaceRepository()..workspaces = [adminWs];
    final container = ProviderContainer(
      overrides: [
        workspaceRepositoryProvider.overrideWith((ref) => repo),
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'u-1', email: 'u@x.com', displayName: 'U'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpPushedModal(tester, container);

    // The delete button sits below the fold in the members list; scroll it in.
    await tester.drag(find.byType(ListView).last, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('Delete Workspace'), findsOneWidget);
    await tester.tap(find.text('Delete Workspace'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('This permanently deletes the workspace'),
      findsOneWidget,
    );
    expect(find.text('Tasks in this workspace: 0'), findsOneWidget);
    expect(
      find.textContaining('members who are not part of another workspace'),
      findsOneWidget,
    );

    final confirmButton = find.widgetWithText(ElevatedButton, 'Delete Workspace');
    expect(confirmButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNull);

    final confirmField = find.ancestor(
      of: find.text('Type "Team" to confirm'),
      matching: find.byType(TextField),
    );
    await tester.enterText(confirmField, 'Team');
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNotNull);

    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(repo.deleteCalls, ['ws-1']);
    expect(container.read(activeWorkspaceProvider).hasWorkspace, isFalse);
    expect(find.byType(WorkspaceManagementModal), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-admins never see the danger zone', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'user-456', email: 'sarah.designer@tasksphere.app', displayName: 'Sarah'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpPushedModal(tester, container);

    expect(find.text('Danger Zone'), findsNothing);
    expect(find.text('Delete Workspace'), findsNothing);
    expect(find.text('New workspace name...'), findsNothing);
    expect(find.text('Invite Member to Workspace'), findsNothing);
    expect(find.text('Switch Workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo user never sees the danger zone', (tester) async {
    // Default providers sign in the demo user, who is the demo workspace's
    // admin but is still barred from destructive actions.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpPushedModal(tester, container);

    expect(find.text('Danger Zone'), findsNothing);
    expect(find.text('Switch Workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admins can remove members and other admins, but not themselves', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = FakeWorkspaceRepository()
      ..workspaces = [
        Workspace(
          id: 'ws-1',
          name: 'Team',
          adminId: 'u-1',
          members: [
            WorkspaceMember(
              id: 'u-1',
              workspaceId: 'ws-1',
              userId: 'u-1',
              email: 'me@x.com',
              role: UserRole.admin,
            ),
            WorkspaceMember(
              id: 'u-2',
              workspaceId: 'ws-1',
              userId: 'u-2',
              email: 'peer@x.com',
              role: UserRole.admin,
            ),
            WorkspaceMember(
              id: 'u-3',
              workspaceId: 'ws-1',
              userId: 'u-3',
              email: 'dev@x.com',
              role: UserRole.member,
            ),
          ],
        ),
      ]
      ..lanes = [KanbanLane(id: 'lane-1', workspaceId: 'ws-1', title: 'To Do')];
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'u-1', email: 'me@x.com', displayName: 'Me'),
          ),
        ),
        isDemoUserProvider.overrideWith((ref) => false),
        workspaceRepositoryProvider.overrideWith((ref) => repo),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeWorkspaceProvider.notifier);
    await notifier.loadInitialData();
    await _pumpModal(tester, container);

    // Removal is offered for the other admin and the member, not for the
    // acting admin's own row.
    expect(find.byIcon(Icons.person_remove_outlined), findsNWidgets(2));

    // Remove the other admin first; the confirm dialog shows their label.
    await tester.tap(find.byIcon(Icons.person_remove_outlined).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Remove peer'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(
      container.read(activeWorkspaceProvider).activeWorkspace.members.map((m) => m.id),
      ['u-1', 'u-3'],
    );
    expect(find.byIcon(Icons.person_remove_outlined), findsOneWidget);

    // The member is removable too; only the admin's own row has no control.
    await tester.tap(find.byIcon(Icons.person_remove_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(
      container.read(activeWorkspaceProvider).activeWorkspace.members.map((m) => m.id),
      ['u-1'],
    );
    expect(find.byIcon(Icons.person_remove_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a member confirms before deleting', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Drive the REAL notifier through the repo so the removal persists.
    final repo = FakeWorkspaceRepository()
      ..workspaces = [
        Workspace(
          id: 'ws-1',
          name: 'Team',
          adminId: 'u-1',
          members: [
            WorkspaceMember(
              id: 'u-1',
              workspaceId: 'ws-1',
              userId: 'u-1',
              email: 'u@x.com',
              role: UserRole.admin,
            ),
            WorkspaceMember(
              id: 'u-2',
              workspaceId: 'ws-1',
              userId: 'u-2',
              email: 'm@x.com',
              role: UserRole.member,
            ),
          ],
        ),
      ]
      ..lanes = [KanbanLane(id: 'lane-1', workspaceId: 'ws-1', title: 'To Do')];
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'u-1', email: 'u@x.com', displayName: 'U'),
          ),
        ),
        isDemoUserProvider.overrideWith((ref) => false),
        workspaceRepositoryProvider.overrideWith((ref) => repo),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeWorkspaceProvider.notifier);
    await notifier.loadInitialData();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: WorkspaceManagementModal())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Cancel keeps the member.
    await tester.tap(find.byIcon(Icons.person_remove_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.memberRemovals, isEmpty);

    // Confirm removes them.
    await tester.tap(find.byIcon(Icons.person_remove_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(repo.memberRemovals, hasLength(1));
  });
}
