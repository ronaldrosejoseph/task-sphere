import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_sphere/core/theme/app_theme.dart';
import 'package:task_sphere/views/analytics/analytics_view.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpAnalytics(WidgetTester tester, Size size, ThemeData theme) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(body: AnalyticsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders KPI cards and charts on a wide desktop layout', (tester) async {
    await pumpAnalytics(tester, const Size(1400, 900), AppTheme.darkTheme);

    expect(find.text('Total Tasks'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Completion Rate'), findsOneWidget);
    expect(find.text('Tasks by Lane'), findsOneWidget);
    expect(find.text('Member Workload'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wraps KPI cards without overflow on a narrow tablet layout', (tester) async {
    await pumpAnalytics(tester, const Size(500, 900), AppTheme.darkTheme);

    expect(find.text('Total Tasks'), findsOneWidget);
    expect(find.text('Member Workload'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders correctly in light mode', (tester) async {
    await pumpAnalytics(tester, const Size(1200, 900), AppTheme.lightTheme);

    expect(find.text('Tasks by Lane'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
