import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_service.dart';
import '../../providers/auth_provider.dart';
import '../navigation/main_navigation_scaffold.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);

    if (user != null) {
      return const MainNavigationScaffold();
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B0F19), Color(0xFF1E1B4B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              color: const Color(0xFF111827).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF374151)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.grid_view_rounded, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Task Sphere',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  'Serverless Kanban Task Management with Supabase & Google Drive API',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
                const SizedBox(height: 24),

                // Sync Mode Status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (SupabaseService.instance.isInitialized
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B))
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (SupabaseService.instance.isInitialized
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B))
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    SupabaseService.instance.isInitialized
                        ? 'Cloud sync enabled - sign in to continue'
                        : 'Offline demo mode - data stays on this device',
                    style: TextStyle(
                      fontSize: 12,
                      color: SupabaseService.instance.isInitialized
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Google Sign-In Button
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(authProvider.notifier).signInWithGoogle();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: Image.network(
                    'https://upload.wikimedia.org/wikipedia/commons/5/53/Google_%22G%22_Logo.svg',
                    height: 20,
                    errorBuilder: (_, _, _) => const Icon(Icons.g_mobiledata, color: Colors.blue),
                  ),
                  label: const Text('Sign in with Google', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),

                // Demo / Offline Bypass Button
                OutlinedButton(
                  onPressed: () {
                    ref.read(authProvider.notifier).setDemoUser();
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    side: const BorderSide(color: Color(0xFF6366F1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Explore Demo Mode (Offline)',
                    style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
