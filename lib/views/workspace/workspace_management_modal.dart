import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/workspace.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';

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
    final activeWs = workspaceState.activeWorkspace;
    final allWs = workspaceState.allWorkspaces;

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
                DropdownButton<UserRole>(
                  value: _selectedRole,
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

            // Members List
            const Text('Current Members', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: activeWs.members.length,
                itemBuilder: (context, index) {
                  final member = activeWs.members[index];
                  final isAdmin = member.role == UserRole.admin;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: isAdmin ? const Color(0xFF6366F1) : Colors.grey,
                      child: Text(member.email[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(member.email, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Role: ${member.role.name.toUpperCase()}'),
                    trailing: isAdmin
                        ? const Chip(label: Text('Admin', style: TextStyle(fontSize: 10)))
                        : const Chip(label: Text('Member', style: TextStyle(fontSize: 10))),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
