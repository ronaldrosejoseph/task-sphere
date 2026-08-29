class AppConfig {
  /// Set via `--dart-define=DEMO_MODE=true` (the Cloudflare Pages build).
  /// Forces in-memory repositories with seeded demo data and blocks
  /// workspace/task/invite creation, so the public demo site never writes
  /// to the production database.
  static const bool isDemoMode = bool.fromEnvironment('DEMO_MODE');
}
