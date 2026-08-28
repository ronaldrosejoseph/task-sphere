import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/task.dart';
import '../../providers/task_provider.dart';
import '../../providers/workspace_provider.dart';
import '../task_detail/task_detail_modal.dart';

class ListCalendarView extends ConsumerStatefulWidget {
  const ListCalendarView({super.key});

  @override
  ConsumerState<ListCalendarView> createState() => _ListCalendarViewState();
}

class _ListCalendarViewState extends ConsumerState<ListCalendarView> with SingleTickerProviderStateMixin {
  late TabController _subTabController;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _subTabController,
          tabs: const [
            Tab(icon: Icon(Icons.format_list_bulleted), text: 'Task List'),
            Tab(icon: Icon(Icons.calendar_month), text: 'Calendar View'),
            Tab(icon: Icon(Icons.archive_outlined), text: 'Archived Tasks'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: const [
              _TaskListView(),
              _CalendarView(),
              _ArchivedTasksView(),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskListView extends ConsumerWidget {
  const _TaskListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).where((t) => !t.isArchived).toList();
    final lanes = ref.watch(activeWorkspaceProvider).lanes;

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: lanes.length,
      itemBuilder: (context, index) {
        final lane = lanes[index];
        final laneTasks = tasks.where((t) => t.laneId == lane.id).toList();

        return ExpansionTile(
          initiallyExpanded: true,
          leading: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: lane.color, shape: BoxShape.circle),
          ),
          title: Text(
            '${lane.title} (${laneTasks.length})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          children: laneTasks.map((task) {
            return ListTile(
              leading: Icon(Icons.circle, size: 10, color: task.priority.color),
              title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Assigned: ${task.assigneeName ?? "Unassigned"} • Priority: ${task.priority.label}'),
              trailing: task.dueDate != null
                  ? Text(DateFormat('MMM dd').format(task.dueDate!))
                  : null,
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => TaskDetailModal(task: task),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}

class _CalendarView extends ConsumerWidget {
  const _CalendarView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).where((t) => t.dueDate != null && !t.isArchived).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Upcoming Task Deadlines',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...tasks.map((task) {
          return Card(
            child: ListTile(
              leading: Icon(Icons.event, color: task.priority.color),
              title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Due: ${DateFormat("EEEE, MMM dd, yyyy").format(task.dueDate!)}'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: task.priority.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  task.priority.label,
                  style: TextStyle(color: task.priority.color, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => TaskDetailModal(task: task),
                );
              },
            ),
          );
        }).toList(),
      ],
    );
  }
}

class _ArchivedTasksView extends ConsumerWidget {
  const _ArchivedTasksView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedTasks = ref.watch(tasksProvider).where((t) => t.isArchived).toList();

    if (archivedTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            const Text('No Archived Tasks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Completed tasks past auto-expiry limit will appear here.', style: TextStyle(color: Colors.grey[400])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: archivedTasks.length,
      itemBuilder: (context, index) {
        final task = archivedTasks[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.archive, color: Colors.grey),
            title: Text(task.title, style: const TextStyle(decoration: TextDecoration.lineThrough)),
            subtitle: Text('Created: ${DateFormat("MMM dd, yyyy").format(task.createdAt)}'),
            trailing: TextButton.icon(
              icon: const Icon(Icons.unarchive, size: 16),
              label: const Text('Restore'),
              onPressed: () {
                ref.read(tasksProvider.notifier).archiveTask(task.id, false);
              },
            ),
          ),
        );
      },
    );
  }
}
