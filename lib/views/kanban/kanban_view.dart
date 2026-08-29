import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../models/task.dart';
import '../../models/lane.dart';
import '../../providers/task_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/lane_manager_dialog.dart';
import '../task_detail/task_detail_modal.dart';

class KanbanView extends ConsumerWidget {
  const KanbanView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceState = ref.watch(activeWorkspaceProvider);
    final allTasks = ref.watch(tasksProvider);
    final lanes = workspaceState.lanes;

    final searchText = ref.watch(taskFilterSearchProvider);
    final selectedPriority = ref.watch(taskFilterPriorityProvider);
    final selectedAssignee = ref.watch(taskFilterAssigneeProvider);
    final showArchived = ref.watch(showArchivedTasksProvider);
    final autoArchiveDays = workspaceState.activeWorkspace.autoArchiveDays;

    final now = DateTime.now();

    // Filter tasks based on auto-expiry threshold & filter bar
    final filteredTasks = allTasks.where((task) {
      // 1. Search Query Filter
      if (searchText.isNotEmpty) {
        final query = searchText.toLowerCase();
        final matchesTitle = task.title.toLowerCase().contains(query);
        final matchesDesc = task.description.toLowerCase().contains(query);
        if (!matchesTitle && !matchesDesc) return false;
      }

      // 2. Priority Filter
      if (selectedPriority != null && task.priority != selectedPriority) {
        return false;
      }

      // 3. Assignee Filter
      if (selectedAssignee != null && task.assigneeEmail != selectedAssignee) {
        return false;
      }

      // 4. Auto-Expiry & Archiving Filter
      final isDoneOrWontDo = lanes.any((l) =>
          l.id == task.laneId &&
          (l.title.toLowerCase() == 'done' || l.title.toLowerCase() == 'wont do'));

      final isExpired = isDoneOrWontDo &&
          now.difference(task.createdAt).inDays >= autoArchiveDays;

      if ((task.isArchived || isExpired) && !showArchived) {
        return false;
      }

      return true;
    }).toList();

    return Column(
      children: [
        // Top Filter Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppTheme.surfaceDark
                : AppTheme.surfaceLight,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.borderDark
                    : AppTheme.borderLight,
              ),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Search Input
                SizedBox(
                  width: 220,
                  height: 40,
                  child: TextField(
                    onChanged: (val) => ref.read(taskFilterSearchProvider.notifier).set(val),
                    decoration: InputDecoration(
                      hintText: 'Search tasks...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Priority Filter Dropdown
                DropdownButton<TaskPriority?>(
                  value: selectedPriority,
                  hint: const Text('All Priorities', style: TextStyle(fontSize: 13)),
                  underline: const SizedBox(),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Priorities')),
                    ...TaskPriority.values.map((p) => DropdownMenuItem(
                          value: p,
                          child: Row(
                            children: [
                              Icon(Icons.circle, size: 8, color: p.color),
                              const SizedBox(width: 6),
                              Text(p.label),
                            ],
                          ),
                        )),
                  ],
                  onChanged: (val) => ref.read(taskFilterPriorityProvider.notifier).set(val),
                ),
                const SizedBox(width: 12),

                // Assignee Filter Dropdown
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: DropdownButton<String?>(
                    value: selectedAssignee,
                    isExpanded: true,
                    hint: const Text('All Assignees', style: TextStyle(fontSize: 13)),
                    underline: const SizedBox(),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Assignees')),
                      ...workspaceState.activeWorkspace.members.map((m) {
                        return DropdownMenuItem(
                          value: m.email,
                          child: Text(
                            m.email.split('@').first,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) =>
                        ref.read(taskFilterAssigneeProvider.notifier).set(val),
                  ),
                ),
                const SizedBox(width: 12),

                // Show Archived Toggle
                FilterChip(
                  selected: showArchived,
                  label: Text(showArchived ? 'Showing Archived' : 'Hide Archived (Auto-Expiry)'),
                  avatar: Icon(
                    showArchived ? Icons.visibility : Icons.visibility_off_outlined,
                    size: 16,
                  ),
                  onSelected: (val) => ref.read(showArchivedTasksProvider.notifier).set(val),
                ),
                const SizedBox(width: 12),

                // Manage Lanes Button (Admin)
                OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const LaneManagerDialog(),
                    );
                  },
                  icon: const Icon(Icons.view_column_rounded, size: 16),
                  label: const Text('Manage Lanes'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 12),

                // New Task Button
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const TaskDetailModal(),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryIndigo,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: const Icon(Icons.add, size: 18, color: Colors.white),
                  label: const Text('New Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),

        // Dynamic Kanban Columns Body
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(20),
            itemCount: lanes.length,
            itemBuilder: (context, index) {
              final lane = lanes[index];
              final laneTasks = filteredTasks.where((t) => t.laneId == lane.id).toList()
                ..sort(compareTasksForBoard);

              return _KanbanColumnWidget(
                lane: lane,
                tasks: laneTasks,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _KanbanColumnWidget extends ConsumerWidget {
  final KanbanLane lane;
  final List<TaskItem> tasks;

  const _KanbanColumnWidget({required this.lane, required this.tasks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 320,
      margin: const EdgeInsets.only(right: 16),
      decoration: AppTheme.glassBoxDecoration(context: context),
      child: DragTarget<TaskItem>(
        onWillAcceptWithDetails: (details) => details.data.laneId != lane.id,
        onAcceptWithDetails: (details) {
          ref.read(tasksProvider.notifier).moveTaskLane(details.data.id, lane.id);
        },
        builder: (context, candidateData, rejectedData) {
          final isHighlight = candidateData.isNotEmpty;

          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: isHighlight
                  ? Border.all(color: lane.color, width: 2)
                  : null,
            ),
            child: Column(
              children: [
                // Lane Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: lane.color.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: lane.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                lane.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: lane.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${tasks.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: lane.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        tooltip: 'Add Task to ${lane.title}',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => TaskDetailModal(initialLaneId: lane.id),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Lane Cards List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return Draggable<TaskItem>(
                        data: task,
                        feedback: SizedBox(
                          width: 300,
                          child: Material(
                            elevation: 8,
                            borderRadius: BorderRadius.circular(16),
                            child: _TaskCardWidget(task: task, isDragging: true),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: _TaskCardWidget(task: task),
                        ),
                        child: _TaskCardWidget(task: task),
                      ).animate().fadeIn(duration: 200.ms, delay: (index * 50).ms);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TaskCardWidget extends StatelessWidget {
  final TaskItem task;
  final bool isDragging;

  const _TaskCardWidget({required this.task, this.isDragging = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOverdue = task.dueDate != null && task.dueDate!.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOverdue ? Colors.redAccent.withValues(alpha: 0.6) : AppTheme.borderDark.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => TaskDetailModal(task: task),
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Priority Pill & Attachment Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: task.priority.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: task.priority.color.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      task.priority.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: task.priority.color,
                      ),
                    ),
                  ),
                  if (task.attachmentPaths.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.attach_file, size: 14, color: Color(0xFF3B82F6)),
                        Text(
                          '${task.attachmentPaths.length}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF3B82F6)),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Title
              Text(
                task.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  task.description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),

              // Subtask Progress Bar
              if (task.subtasks.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Subtasks',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                    Text(
                      '${(task.subtasksProgress * 100).toInt()}%',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: task.subtasksProgress,
                  backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 4,
                ),
                const SizedBox(height: 10),
              ],

              // Footer: Assignee & Due Date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Assignee Avatar / Name
                  Expanded(
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: AppTheme.primaryIndigo,
                          child: Text(
                            (task.assigneeName ?? 'U')[0].toUpperCase(),
                            style: const TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            task.assigneeName ?? 'Unassigned',
                            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Due Date Badge
                  if (task.dueDate != null)
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 12,
                          color: isOverdue ? Colors.redAccent : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('MMM dd').format(task.dueDate!),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                            color: isOverdue ? Colors.redAccent : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
