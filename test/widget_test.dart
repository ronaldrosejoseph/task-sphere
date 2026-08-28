import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_sphere/main.dart';

void main() {
  testWidgets('Task Sphere app initializes and renders successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TaskSphereApp()));
    await tester.pumpAndSettle();
    expect(find.byType(TaskSphereApp), findsOneWidget);
    expect(find.text('Engineering & Design Team'), findsWidgets);
  });
}
