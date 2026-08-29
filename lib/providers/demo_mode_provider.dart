import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';

/// Overridable in tests so demo-mode behavior can be exercised without
/// recompiling with the DEMO_MODE dart-define.
final demoModeProvider = Provider<bool>((_) => AppConfig.isDemoMode);
