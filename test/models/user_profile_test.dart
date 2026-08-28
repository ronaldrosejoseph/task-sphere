import 'package:flutter_test/flutter_test.dart';
import 'package:task_sphere/models/user_profile.dart';

void main() {
  group('UserProfile', () {
    test('demo factory provides a stable demo user', () {
      final demo = UserProfile.demo();
      expect(demo.id, 'demo-user-123');
      expect(demo.email, 'alex.admin@tasksphere.app');
      expect(demo.displayName, 'Alex Morgan (Admin)');
      expect(demo.avatarUrl, isNull);
    });
  });
}
