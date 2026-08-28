import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/task_provider.dart';
import '../../providers/workspace_provider.dart';

class AnalyticsView extends ConsumerWidget {
  const AnalyticsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    final lanes = ref.watch(activeWorkspaceProvider).lanes;

    final totalTasks = tasks.length;
    final doneTasksCount = tasks.where((t) {
      final lane = lanes.firstWhere((l) => l.id == t.laneId, orElse: () => lanes.first);
      return lane.title.toLowerCase() == 'done';
    }).length;

    final completionRate = totalTasks > 0 ? (doneTasksCount / totalTasks * 100).toStringAsFixed(1) : '0';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Workspace Analytics & Velocity', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Track team workload, status distribution, and completion rates.', style: TextStyle(color: Colors.grey[400])),
          const SizedBox(height: 24),

          // KPI Cards Row
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'Total Tasks',
                  value: '$totalTasks',
                  icon: Icons.task_alt,
                  color: Colors.blueAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: 'Completed',
                  value: '$doneTasksCount',
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: 'Completion Rate',
                  value: '$completionRate%',
                  icon: Icons.trending_up,
                  color: const Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Charts Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pie Chart: Status Distribution
                  Expanded(
                    flex: isWide ? 1 : 0,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Tasks by Lane', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 220,
                              child: PieChart(
                                PieChartData(
                                  sectionsSpace: 4,
                                  centerSpaceRadius: 40,
                                  sections: lanes.map((lane) {
                                    final count = tasks.where((t) => t.laneId == lane.id).length;
                                    return PieChartSectionData(
                                      color: lane.color,
                                      value: count.toDouble(),
                                      title: '$count',
                                      radius: 50,
                                      titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: lanes.map((lane) {
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(width: 10, height: 10, color: lane.color),
                                    const SizedBox(width: 4),
                                    Text(lane.title, style: const TextStyle(fontSize: 12)),
                                  ],
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (isWide) const SizedBox(width: 20) else const SizedBox(height: 20),

                  // Member Workload Distribution
                  Expanded(
                    flex: isWide ? 1 : 0,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Member Workload', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 220,
                              child: BarChart(
                                BarChartData(
                                  borderData: FlBorderData(show: false),
                                  titlesData: const FlTitlesData(
                                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  ),
                                  barGroups: [
                                    BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: 3, color: const Color(0xFF6366F1))]),
                                    BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 2, color: const Color(0xFF10B981))]),
                                    BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: 4, color: const Color(0xFFF59E0B))]),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text('Tasks assigned per team member', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
