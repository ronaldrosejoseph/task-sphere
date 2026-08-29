import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/task.dart';
import '../../models/workspace.dart';
import '../../providers/task_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../core/theme/app_theme.dart';

class AnalyticsView extends ConsumerWidget {
  const AnalyticsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    final workspaceState = ref.watch(activeWorkspaceProvider);
    final lanes = workspaceState.lanes;
    final members = workspaceState.activeWorkspace.members;

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

          // KPI Cards (row on wide screens, wrap on tablet and below)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              final cards = [
                _KpiCard(
                  title: 'Total Tasks',
                  value: '$totalTasks',
                  icon: Icons.task_alt,
                  color: Colors.blueAccent,
                ),
                _KpiCard(
                  title: 'Completed',
                  value: '$doneTasksCount',
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF10B981),
                ),
                _KpiCard(
                  title: 'Completion Rate',
                  value: '$completionRate%',
                  icon: Icons.trending_up,
                  color: const Color(0xFF8B5CF6),
                ),
              ];

              if (isWide) {
                return Row(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(child: cards[i]),
                    ],
                  ],
                );
              }

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final card in cards)
                    SizedBox(width: 280, child: card),
                ],
              );
            },
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
                              child: _MemberWorkloadChart(tasks: tasks, members: members),
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

class _MemberWorkloadChart extends StatelessWidget {
  final List<TaskItem> tasks;
  final List<WorkspaceMember> members;

  const _MemberWorkloadChart({required this.tasks, required this.members});

  static const _palette = [
    Color(0xFF6366F1),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFF8B5CF6),
  ];

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final member in members) {
      counts[member.email] = 0;
    }
    var unassigned = 0;
    for (final task in tasks) {
      final email = task.assigneeEmail;
      if (email == null || email.isEmpty) {
        unassigned += 1;
      } else if (counts.containsKey(email)) {
        counts[email] = counts[email]! + 1;
      } else {
        counts[email] = 1;
      }
    }

    final entries = <(String, String, int)>[
      for (final member in members)
        (
          member.email,
          member.email.split('@').first,
          counts[member.email] ?? 0,
        ),
      if (unassigned > 0) ('unassigned', 'Unassigned', unassigned),
    ];

    final total = entries.fold<int>(0, (sum, e) => sum + e.$3);
    if (total == 0) {
      return Center(
        child: Text(
          'No tasks assigned yet',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
      );
    }

    final maxCount = entries.map((e) => e.$3).reduce((a, b) => a > b ? a : b);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final axisColor = isDark ? AppTheme.mutedDark : AppTheme.mutedLight;
    final tooltipBackground = isDark ? AppTheme.cardDark : const Color(0xFF111827);
    final tooltipForeground = Colors.white;

    return BarChart(
      BarChartData(
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        maxY: (maxCount + 1).toDouble(),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => tooltipBackground,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = entries[group.x].$2;
              return BarTooltipItem(
                '$label\n',
                TextStyle(
                  color: tooltipForeground,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  TextSpan(
                    text: '${rod.toY.round()} task${rod.toY.round() == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: tooltipForeground.withValues(alpha: 0.85),
                      fontSize: 11,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(fontSize: 10, color: axisColor),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= entries.length) return const SizedBox.shrink();
                final label = entries[index].$2;
                final short = label.length > 7 ? '${label.substring(0, 7)}…' : label;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(short, style: TextStyle(fontSize: 9, color: axisColor)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].$3.toDouble(),
                  color: _palette[i % _palette.length],
                  width: 18,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
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
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
