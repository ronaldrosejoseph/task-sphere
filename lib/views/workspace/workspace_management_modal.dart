import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/workspace.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../providers/demo_mode_provider.dart';
import '../../providers/task_provider.dart';

class WorkspaceManagementModal extends ConsumerStatefulWidget {
  const WorkspaceManagementModal({super.key});

  @override
  ConsumerState<WorkspaceManagementModal> createState() => _WorkspaceManagementModalState();
}

class _WorkspaceManagementModalState extends ConsumerState<WorkspaceManagementModal> {
  final _emailController = TextEditingController();
  final _newWsController = TextEditingController();
  UserRole _selectedRole = UserRole.member;

  @override
  void dispose() {
    _emailController.dispose();
    _newWsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspaceState = ref.watch(activeWorkspaceProvider);
    final demoMode = ref.watch(demoModeProvider);
    final currentUser = ref.watch(authProvider);
    final activeWs = workspaceState.activeWorkspace;
    final allWs = workspaceState.allWorkspaces;
    final isAdmin = ref.read(activeWorkspaceProvider.notifier).isAdmin(currentUser);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.workspaces, color: Color(0xFF6366F1)),
                    const SizedBox(width: 10),
                    Text(
                      'Workspaces & Roles',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24),

            // Workspace Switcher
            const Text('Switch Workspace', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: allWs.map((ws) {
                final isCurrent = ws.id == activeWs.id;
                return ChoiceChip(
                  label: Text(ws.name),
                  selected: isCurrent,
                  onSelected: (selected) {
                    if (selected) {
                      ref.read(activeWorkspaceProvider.notifier).switchWorkspace(ws);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            if (!demoMode) ...[
              // Create New Workspace
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newWsController,
                      decoration: InputDecoration(
                        hintText: 'New workspace name...',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final name = _newWsController.text.trim();
                      if (name.isNotEmpty) {
                        final user = ref.read(authProvider);
                        ref.read(activeWorkspaceProvider.notifier).createWorkspace(
                              name,
                              user?.id ?? 'demo-user-123',
                              user?.email ?? 'admin@tasksphere.app',
                            );
                        _newWsController.clear();
                      }
                    },
                    child: const Text('Create'),
                  ),
                ],
              ),
              const Divider(height: 32),

              // Invite Member & Assign Role
              const Text('Invite Member to Workspace', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: 'Member Google email...',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 130,
                    child: DropdownButton<UserRole>(
                      value: _selectedRole,
                      isExpanded: true,
                      items: UserRole.values.map((r) {
                        return DropdownMenuItem(
                          value: r,
                          child: Text(r.name.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedRole = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      final email = _emailController.text.trim();
                      if (email.isNotEmpty) {
                        ref.read(activeWorkspaceProvider.notifier).inviteMember(email, _selectedRole);
                        _emailController.clear();
                      }
                    },
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text('Invite'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Members List + Danger Zone (scrolls together so the dialog
            // never overflows on short viewports)
            Expanded(
              child: ListView(
                children: [
                  const Text('Current Members', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final member in activeWs.members) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: member.role == UserRole.admin ? const Color(0xFF6366F1) : Colors.grey,
                        child: Text(member.email[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(member.email, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Role: ${member.role.name.toUpperCase()}'),
                      trailing: member.role == UserRole.admin
                          ? const Chip(label: Text('Admin', style: TextStyle(fontSize: 10)))
                          : const Chip(label: Text('Member', style: TextStyle(fontSize: 10))),
                    ),
                  ],

                  // Danger Zone (admins only, hidden in demo mode)
                  if (!demoMode && isAdmin) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Danger Zone',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Delete this workspace and everything in it. Tasks, lanes, and members are permanently removed.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _confirmDeleteWorkspace,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.delete_forever_outlined, size: 18),
                              label: const Text('Delete Workspace'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteWorkspace() async {
    final ws = ref.read(activeWorkspaceProvider).activeWorkspace;
    final taskCount = ref.read(tasksProvider).length;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final matches = controller.text.trim() == ws.name;
          return AlertDialog(
            title: Text('Delete "${ws.name}"?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This permanently deletes the workspace, all of its kanban lanes, and every task and member in it. This cannot be undone.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tasks in this workspace: $taskCount',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Type "${ws.name}" to confirm',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Delete Workspace'),
              ),
            ],
          );
        },
      ),
    );
    // The dialog's exit animation still references the controller, so it
    // must outlive the pop; the transient dialog is disposed with the route.
    if (confirmed != true || !mounted) return;
    await ref.read(activeWorkspaceProvider.notifier).deleteWorkspace(ws.id);
    if (mounted) Navigator.pop(context);
  }
}
