import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/models/lane.dart';
import 'package:task_sphere/models/workspace.dart';
import 'package:task_sphere/providers/demo_mode_provider.dart';
import 'package:task_sphere/providers/workspace_provider.dart';
import 'package:task_sphere/views/workspace/workspace_management_modal.dart';

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
}
