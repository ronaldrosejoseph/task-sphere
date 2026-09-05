import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/workspace_provider.dart';
import '../../providers/auth_provider.dart';
import '../kanban/kanban_view.dart';
import '../list_calendar/list_calendar_view.dart';
import '../analytics/analytics_view.dart';
import '../settings/settings_view.dart';
import '../workspace/workspace_management_modal.dart';

class MainNavigationScaffold extends ConsumerStatefulWidget {
  const MainNavigationScaffold({super.key});

  @override
  ConsumerState<MainNavigationScaffold> createState() => _MainNavigationScaffoldState();
}

class _MainNavigationScaffoldState extends ConsumerState<MainNavigationScaffold> {
  int _selectedIndex = 0;

  final List<Widget> _views = const [
    KanbanView(),
    ListCalendarView(),
    AnalyticsView(),
    SettingsView(),
  ];

  @override
  Widget build(BuildContext context) {
    final workspaceState = ref.watch(activeWorkspaceProvider);
    final activeWs = workspaceState.activeWorkspace;
    final currentUser = ref.watch(authProvider);

    // A realtime kick from the active workspace sets the notice; show it once
    // and clear it so it never re-fires on rebuilds.
    ref.listen(activeWorkspaceProvider, (previous, next) {
      final removed = next.removedFromWorkspace;
      if (removed == null || removed.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // The shell is the root route (AuthScreen swaps it in inline), so
        // popping down to the first route dismisses any open dialog — the
        // task detail modal, lane manager, or workspace manager — without
        // ever popping the shell itself.
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You were removed from $removed')),
        );
      });
      ref.read(activeWorkspaceProvider.notifier).clearRemovedFromWorkspace();
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 800;

        if (isDesktop) {
          // Desktop / Web Sidebar Layout
          return Scaffold(
            body: Row(
              children: [
                // Left Navigation Sidebar
                Material(
                  color: Theme.of(context).cardColor,
                  child: Container(
                    width: 250,
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    child: Column(
                    children: [
                      // App Header & Logo
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(13),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Task Sphere',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Serverless Kanban',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      // Workspace Switcher Pill
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => const WorkspaceManagementModal(),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.workspaces, color: Color(0xFF6366F1), size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        workspaceState.hasWorkspace ? activeWs.name : 'No Workspace',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        workspaceState.hasWorkspace ? 'Admin Access' : 'Create Workspace',
                                        style: const TextStyle(fontSize: 10, color: Color(0xFF6366F1)),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.unfold_more, size: 16, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Sidebar Navigation Items
                      _SidebarNavItem(
                        icon: Icons.dashboard_outlined,
                        selectedIcon: Icons.dashboard,
                        label: 'Kanban Board',
                        isSelected: _selectedIndex == 0,
                        onTap: () => setState(() => _selectedIndex = 0),
                      ),
                      _SidebarNavItem(
                        icon: Icons.format_list_bulleted,
                        selectedIcon: Icons.format_list_bulleted,
                        label: 'List & Calendar',
                        isSelected: _selectedIndex == 1,
                        onTap: () => setState(() => _selectedIndex = 1),
                      ),
                      _SidebarNavItem(
                        icon: Icons.bar_chart_outlined,
                        selectedIcon: Icons.bar_chart,
                        label: 'Analytics',
                        isSelected: _selectedIndex == 2,
                        onTap: () => setState(() => _selectedIndex = 2),
                      ),
                      _SidebarNavItem(
                        icon: Icons.settings_outlined,
                        selectedIcon: Icons.settings,
                        label: 'Settings',
                        isSelected: _selectedIndex == 3,
                        onTap: () => setState(() => _selectedIndex = 3),
                      ),

                      const Spacer(),

                      // Bottom User Profile Card
                      const Divider(height: 1),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF6366F1),
                          child: Text((currentUser?.displayName ?? 'A')[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(
                          currentUser?.displayName ?? 'Admin User',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          currentUser?.email ?? 'Serverless Sync',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.logout, size: 20, color: Colors.grey),
                          tooltip: 'Sign out',
                          onPressed: () =>
                              ref.read(authProvider.notifier).signOut(),
                        ),
                      ),
                    ],
                  ),
                ),
                ),

                // Main Content View
                Expanded(child: _views[_selectedIndex]),
              ],
            ),
          );
        }

        // Mobile Layout (Bottom Navigation Bar)
        return Scaffold(
          appBar: AppBar(
            title: Text(workspaceState.hasWorkspace ? activeWs.name : 'No Workspace'),
            actions: [
              IconButton(
                icon: const Icon(Icons.workspaces_outlined),
                tooltip: 'Workspaces',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const WorkspaceManagementModal(),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.grey),
                tooltip: 'Sign out',
                onPressed: () =>
                    ref.read(authProvider.notifier).signOut(),
              ),
            ],
          ),
          body: _views[_selectedIndex],
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) => setState(() => _selectedIndex = index),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Kanban'),
              BottomNavigationBarItem(icon: Icon(Icons.format_list_bulleted), label: 'List'),
              BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Analytics'),
              BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        );
      },
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        decoration: isSelected
            ? BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              )
            : null,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          selected: isSelected,
          leading: Icon(
            isSelected ? selectedIcon : icon,
            color: isSelected ? Colors.white : Colors.grey,
          ),
          title: Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : null,
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
