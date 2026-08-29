class UserProfile {
  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;

  UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
  });

  /// Id of the seeded sandbox user; demo-session guards compare against it.
  static const demoUserId = 'demo-user-123';

  factory UserProfile.demo() {
    return UserProfile(
      id: demoUserId,
      email: 'alex.admin@tasksphere.app',
      displayName: 'Alex Morgan (Admin)',
      avatarUrl: null,
    );
  }
}
