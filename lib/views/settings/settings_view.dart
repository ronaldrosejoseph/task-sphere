import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/theme_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/services/supabase_service.dart';
import '../kanban/widgets/lane_manager_dialog.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  Future<void> _promptRename(BuildContext context, WidgetRef ref) async {
    final workspace = ref.read(activeWorkspaceProvider).activeWorkspace;
    final controller = TextEditingController(text: workspace.name);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename workspace'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Shown in the sidebar, app bar, and notifications.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 40,
              decoration: const InputDecoration(
                hintText: 'e.g. Design Studio',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // The dialog's exit animation still references the controller, so it
    // must outlive the pop; the transient dialog is disposed with the route.
    if (saved != true || controller.text.trim().isEmpty) return;
    ref.read(activeWorkspaceProvider.notifier).updateWorkspaceName(controller.text);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDemoUser = ref.watch(isDemoUserProvider);
    final workspaceState = ref.watch(activeWorkspaceProvider);
    final isAdmin = ref
        .read(activeWorkspaceProvider.notifier)
        .isAdmin(ref.watch(authProvider));
    final activeWorkspace = workspaceState.activeWorkspace;
    final autoArchiveDays = activeWorkspace.autoArchiveDays;
    final showArchived = activeWorkspace.showArchivedTasks;
    final effectiveLaneIds = activeWorkspace.autoExpiryLaneIds;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('App Settings & Preferences', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Configure kanban lanes, auto-expiry task archiving, themes, and serverless sync accounts.', style: TextStyle(color: Colors.grey[400])),
        const SizedBox(height: 24),

        // Admin-only: lanes and archiving are workspace settings. The demo
        // sandbox is read-only, so its rename control is hidden entirely.
        if (isAdmin) ...[
        if (!isDemoUser)
          Card(
            child: ListTile(
              leading: const Icon(Icons.drive_file_rename_outline, color: Color(0xFF6366F1)),
              title: const Text('Workspace Name', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                activeWorkspace.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.grey),
                tooltip: 'Rename workspace',
                onPressed: () => _promptRename(context, ref),
              ),
            ),
          ),
        if (!isDemoUser) const SizedBox(height: 20),

        // Manage Lanes
        Card(
          child: ListTile(
            leading: const Icon(Icons.view_column_rounded, color: Color(0xFF6366F1)),
            title: const Text('Manage Kanban Lanes', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Add custom columns, reorder, or update accent colors'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => const LaneManagerDialog(),
              );
            },
          ),
        ),
        const SizedBox(height: 20),

        // Auto-Expiry & Archiving Threshold
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Expanded lets the long title wrap on narrow phones instead
                // of overflowing the card; the icon stays top-aligned.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.inventory_2_outlined, color: Color(0xFF6366F1)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Completed Tasks Auto-Expiry',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose which lanes auto-hide completed tasks from the active Kanban view after a set period. Old tasks remain searchable in the Archive tab.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                ),
                const SizedBox(height: 16),
                // runSpacing separates the wrapped chip rows on phones.
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [7, 14, 30, 90, 999].map((days) {
                    final label = days == 999 ? 'Never' : '$days Days';
                    final isSelected = autoArchiveDays == days;
                    return ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          ref.read(activeWorkspaceProvider.notifier).updateAutoArchiveThreshold(days);
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // Lanes whose tasks auto-hide after the threshold above.
                // New workspaces come pre-selected with Done / Wont Do;
                // deselecting every lane disables auto-expiry.
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: workspaceState.lanes.map((lane) {
                    return FilterChip(
                      avatar: CircleAvatar(
                        backgroundColor: lane.color,
                        radius: 6,
                      ),
                      label: Text(lane.title),
                      selected: effectiveLaneIds.contains(lane.id),
                      onSelected: (_) {
                        final next = {...effectiveLaneIds};
                        if (!next.remove(lane.id)) next.add(lane.id);
                        ref
                            .read(activeWorkspaceProvider.notifier)
                            .updateAutoExpiryLanes(next.toList());
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: showArchived,
                  onChanged: (val) => ref
                      .read(activeWorkspaceProvider.notifier)
                      .updateShowArchivedTasks(val ?? false),
                  title: const Text('Show archived tasks on the board'),
                  subtitle: const Text(
                    'When off, archived and auto-expired tasks are hidden from the Kanban view',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        ],

        // Theme Toggle
        Card(
          child: ListTile(
            leading: Icon(
              themeMode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode,
              color: const Color(0xFFF59E0B),
            ),
            title: const Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(themeMode == ThemeMode.dark ? 'Dark Mode (OLED Glassmorphism)' : 'Light Mode'),
            trailing: Switch(
              value: themeMode == ThemeMode.dark,
              onChanged: (_) => ref.read(themeModeProvider.notifier).toggleTheme(),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Connected Cloud Services Status
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Connected Cloud & Sync Accounts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),

                // Supabase Connection Status
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.cloud_done,
                    color: (isDemoUser || !SupabaseService.instance.isInitialized) ? Colors.orangeAccent : const Color(0xFF10B981),
                  ),
                  title: const Text('Supabase Realtime WebSockets'),
                  subtitle: Text(
                    isDemoUser
                        ? 'Demo Mode: seeded data, changes are not saved'
                        : SupabaseService.instance.isInitialized
                            ? 'Connected to live PostgreSQL database'
                            : 'Demo Mode (Offline / In-Memory)',
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ((isDemoUser || !SupabaseService.instance.isInitialized) ? Colors.orangeAccent : const Color(0xFF10B981)).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (isDemoUser || !SupabaseService.instance.isInitialized) ? 'DEMO MODE' : 'ONLINE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: (isDemoUser || !SupabaseService.instance.isInitialized) ? Colors.orangeAccent : const Color(0xFF10B981),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
