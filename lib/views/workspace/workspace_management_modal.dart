import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/workspace.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
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
    final isDemoUser = ref.watch(isDemoUserProvider);
    final currentUser = ref.watch(authProvider);
    final activeWs = workspaceState.activeWorkspace;
    final allWs = workspaceState.allWorkspaces;
    final isAdmin = ref.read(activeWorkspaceProvider.notifier).isAdmin(currentUser);
    final canCreate = ref.watch(canCreateWorkspaceProvider).value ?? false;

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
                Flexible(
                  child: Row(
                    children: [
                      const Icon(Icons.workspaces, color: Color(0xFF6366F1)),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Workspaces & Roles',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
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

            if (!isDemoUser && ((allWs.isEmpty && canCreate) || isAdmin)) ...[
              // Create New Workspace (everyone without a workspace needs the
              // entry point; members of existing ones are admin-only).
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
            ],
            if (!isDemoUser && isAdmin) ...[
              // Invite Member & Assign Role
              const Text('Invite Member to Workspace', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              // Email field spans the full width so it stays easy to type on
              // phones; role + Invite sit on their own row below.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      hintText: 'Member Google email...',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Wraps on the narrowest phones; gap keeps rows distinct.
                  Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 120,
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
                      ElevatedButton.icon(
                        onPressed: () {
                          final email = _emailController.text.trim();
                          if (email.isNotEmpty) {
                            ref.read(activeWorkspaceProvider.notifier).inviteMember(email, _selectedRole);
                            _emailController.clear();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        icon: const Icon(Icons.send, size: 16),
                        label: const Text('Invite'),
                      ),
                    ],
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
                        child: Text(member.displayLabel[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(
                        member.displayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        member.displayName == null
                            ? 'Role: ${member.role.name.toUpperCase()}'
                            : member.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isDemoUser && isAdmin)
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Edit display name',
                              onPressed: () => _editDisplayName(member),
                            ),
                          if (!isDemoUser && isAdmin && _canRemoveMember(member, activeWs))
                            IconButton(
                              icon: const Icon(Icons.person_remove_outlined, size: 18, color: Colors.redAccent),
                              tooltip: 'Remove from workspace',
                              onPressed: () => _confirmRemoveMember(member),
                            ),
                          if (member.role == UserRole.admin)
                            const Chip(label: Text('Admin', style: TextStyle(fontSize: 10)))
                          else
                            const Chip(label: Text('Member', style: TextStyle(fontSize: 10))),
                        ],
                      ),
                    ),
                  ],

                  // Danger Zone (real admins only, hidden in the demo sandbox)
                  if (!isDemoUser && isAdmin) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
                      ),
                      child: SizedBox(
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
                const SizedBox(height: 8),
                const Text(
                  'Warning: members who are not part of another workspace will lose access to the app.',
                  style: TextStyle(fontSize: 13, color: Colors.redAccent),
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

  /// Whether an admin may remove [member]: never your own row, and never
  /// the workspace's last admin (removing them would orphan the workspace).
  bool _canRemoveMember(WorkspaceMember member, Workspace ws) {
    final currentUser = ref.read(authProvider);
    final userEmail = currentUser?.email;
    final isSelf =
        (member.userId != null && member.userId == currentUser?.id) ||
            (userEmail != null && member.email.toLowerCase() == userEmail.toLowerCase());
    if (isSelf) return false;
    if (member.role != UserRole.admin) return true;
    final adminCount = ws.members.where((m) => m.role == UserRole.admin).length;
    return adminCount > 1;
  }

  Future<void> _confirmRemoveMember(WorkspaceMember member) async {
    final ws = ref.read(activeWorkspaceProvider).activeWorkspace;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${member.displayLabel}?'),
        content: Text(
          '${member.displayLabel} will lose access to "${ws.name}" immediately. '
          'Any tickets they created stay in the workspace.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(activeWorkspaceProvider.notifier).removeMember(member);
  }

  Future<void> _editDisplayName(WorkspaceMember member) async {
    final controller = TextEditingController(text: member.displayName ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Display name for ${member.email}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Shown on cards and filters instead of the email. '
              'Leave empty to keep the email name.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 32,
              decoration: const InputDecoration(
                hintText: 'e.g. Alex Morgan',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
              ),
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
    if (saved != true || !mounted) return;
    ref.read(activeWorkspaceProvider.notifier).updateMemberDisplayName(
          member.id,
          controller.text,
        );
  }
}
