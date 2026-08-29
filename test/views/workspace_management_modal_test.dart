import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/models/lane.dart';
import 'package:task_sphere/models/user_profile.dart';
import 'package:task_sphere/models/workspace.dart';
import 'package:task_sphere/providers/auth_provider.dart';
import 'package:task_sphere/providers/demo_mode_provider.dart';
import 'package:task_sphere/providers/workspace_provider.dart';
import 'package:task_sphere/views/workspace/workspace_management_modal.dart';

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
  final ws = Workspace(id: 'ws-1', name: 'Team', adminId: 'a');
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
  testWidgets('shows create workspace and invite sections normally', (tester) async {
    final container = ProviderContainer(
      overrides: [
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

  testWidgets('demo mode hides create workspace and invite sections', (tester) async {
    final container = ProviderContainer(
      overrides: [
        demoModeProvider.overrideWithValue(true),
        activeWorkspaceProvider.overrideWith(() => _FakeWorkspaceNotifier(_state())),
      ],
    );
    addTearDown(container.dispose);
    await _pumpModal(tester, container);

    expect(find.text('Switch Workspace'), findsOneWidget);
    expect(find.text('Current Members'), findsOneWidget);
    expect(find.text('New workspace name...'), findsNothing);
    expect(find.text('Invite Member to Workspace'), findsNothing);
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

  testWidgets('admin sees the danger zone and must type the name to delete', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpPushedModal(tester, container);

    // The danger zone sits below the fold in the members list; scroll it in.
    await tester.drag(find.byType(ListView).last, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('Danger Zone'), findsOneWidget);
    await tester.tap(find.text('Delete Workspace'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('This permanently deletes the workspace'),
      findsOneWidget,
    );
    expect(find.text('Tasks in this workspace: 5'), findsOneWidget);

    final confirmButton = find.widgetWithText(ElevatedButton, 'Delete Workspace');
    expect(confirmButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNull);

    final confirmField = find.ancestor(
      of: find.text('Type "Engineering & Design Team" to confirm'),
      matching: find.byType(TextField),
    );
    await tester.enterText(confirmField, 'Engineering & Design Team');
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNotNull);

    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

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
    expect(find.text('Switch Workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo mode hides the danger zone even for admins', (tester) async {
    final container = ProviderContainer(
      overrides: [demoModeProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    await pumpPushedModal(tester, container);

    expect(find.text('Danger Zone'), findsNothing);
    expect(find.text('Switch Workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
