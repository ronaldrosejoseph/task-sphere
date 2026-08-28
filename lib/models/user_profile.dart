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

  factory UserProfile.demo() {
    return UserProfile(
      id: 'demo-user-123',
      email: 'alex.admin@tasksphere.app',
      displayName: 'Alex Morgan (Admin)',
      avatarUrl: null,
    );
  }
}
