import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/theme_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/services/supabase_service.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final workspaceState = ref.watch(activeWorkspaceProvider);
    final autoArchiveDays = workspaceState.activeWorkspace.autoArchiveDays;
    final currentUser = ref.watch(authProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('App Settings & Preferences', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Configure auto-expiry task archiving, themes, and serverless sync accounts.', style: TextStyle(color: Colors.grey[400])),
        const SizedBox(height: 24),

        // Auto-Expiry & Archiving Threshold
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: Color(0xFF6366F1)),
                    SizedBox(width: 10),
                    Text('Completed Tasks Auto-Expiry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Automatically hide completed (Done / Wont Do) tasks from the active Kanban view after a set period. Old tasks remain searchable in the Archive tab.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

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

                // Google Account
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_circle, color: Color(0xFF3B82F6)),
                  title: Text(currentUser?.displayName ?? 'Google Drive Sync'),
                  subtitle: Text(currentUser?.email ?? 'Sign in with Google to enable Drive attachments'),
                  trailing: ElevatedButton(
                    onPressed: () {
                      if (currentUser == null) {
                        ref.read(authProvider.notifier).signInWithGoogle();
                      } else {
                        ref.read(authProvider.notifier).signOut();
                      }
                    },
                    child: Text(currentUser == null ? 'Sign In' : 'Sign Out'),
                  ),
                ),
                const Divider(),

                // Supabase Connection Status
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.cloud_done,
                    color: SupabaseService.instance.isInitialized ? const Color(0xFF10B981) : Colors.orangeAccent,
                  ),
                  title: const Text('Supabase Realtime WebSockets'),
                  subtitle: Text(
                    SupabaseService.instance.isInitialized
                        ? 'Connected to live PostgreSQL database'
                        : 'Demo Mode (Offline / In-Memory)',
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (SupabaseService.instance.isInitialized ? const Color(0xFF10B981) : Colors.orangeAccent).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      SupabaseService.instance.isInitialized ? 'ONLINE' : 'DEMO MODE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: SupabaseService.instance.isInitialized ? const Color(0xFF10B981) : Colors.orangeAccent,
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
