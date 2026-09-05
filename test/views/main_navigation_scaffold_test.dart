import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/core/repositories/workspace_repository.dart';
import 'package:task_sphere/core/theme/app_theme.dart';
import 'package:task_sphere/models/user_profile.dart';
import 'package:task_sphere/models/workspace.dart';
import 'package:task_sphere/providers/auth_provider.dart';
import 'package:task_sphere/views/navigation/main_navigation_scaffold.dart';

import '../providers/repository_provider_test.dart' show FakeWorkspaceRepository;

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this.user);

  final UserProfile? user;

  @override
  UserProfile? build() => user;
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpScaffold(WidgetTester tester,
      {required FakeWorkspaceRepository repo}) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        workspaceRepositoryProvider.overrideWith((ref) => repo),
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            UserProfile(id: 'a', email: 'a@x.com', displayName: 'A'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MainNavigationScaffold(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a kick from the active workspace closes open dialogs and shows a notice',
      (tester) async {
    final repo = FakeWorkspaceRepository()
      ..workspaces = [
        Workspace(id: 'ws-1', name: 'Old Team', adminId: 'a'),
        Workspace(id: 'ws-2', name: 'Fresh Team', adminId: 'other'),
      ];
    await pumpScaffold(tester, repo: repo);

    // Open the new-task dialog from the kanban FAB.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Create New Task'), findsOneWidget);

    // The admin removes the user from the active workspace; the membership
    // channel reloads and the kick lands.
    repo.workspaces.removeWhere((w) => w.id == 'ws-1');
    repo.membershipEvents.add(null);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // The dialog is dismissed and the one-shot notice explains the removal.
    expect(find.text('Create New Task'), findsNothing);
    expect(find.text('You were removed from Old Team'), findsOneWidget);
  });

  testWidgets('no notice repeats after the state settles', (tester) async {
    final repo = FakeWorkspaceRepository()
      ..workspaces = [
        Workspace(id: 'ws-1', name: 'Old Team', adminId: 'a'),
        Workspace(id: 'ws-2', name: 'Fresh Team', adminId: 'other'),
      ];
    await pumpScaffold(tester, repo: repo);

    repo.workspaces.removeWhere((w) => w.id == 'ws-1');
    repo.membershipEvents.add(null);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('You were removed from Old Team'), findsOneWidget);

    // Let the snackbar's 4s display elapse.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('You were removed from Old Team'), findsNothing);

    // Another unrelated membership change (e.g. a role edit in ws-2) must
    // not re-show the stale notice.
    repo.membershipEvents.add(null);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('You were removed from Old Team'), findsNothing);
  });
}
