import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/services/supabase_service.dart';
import 'core/services/notification_service.dart';
import 'providers/theme_provider.dart';
import 'views/auth/auth_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Local Push Notifications
  await NotificationService.instance.init();

  // Read Supabase credentials from environment
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  await SupabaseService.instance.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const ProviderScope(child: TaskSphereApp()));
}

class TaskSphereApp extends ConsumerWidget {
  const TaskSphereApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Task Sphere',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const AuthScreen(),
    );
  }
}
