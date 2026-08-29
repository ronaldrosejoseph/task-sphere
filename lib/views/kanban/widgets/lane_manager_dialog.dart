import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/lane.dart';
import '../../../providers/task_provider.dart';
import '../../../providers/workspace_provider.dart';

class LaneManagerDialog extends ConsumerStatefulWidget {
  const LaneManagerDialog({super.key});

  @override
  ConsumerState<LaneManagerDialog> createState() => _LaneManagerDialogState();
}

class _LaneManagerDialogState extends ConsumerState<LaneManagerDialog> {
  final _newLaneController = TextEditingController();
  Color _selectedColor = const Color(0xFF6366F1);

  final List<Color> _presetColors = const [
    Color(0xFF3B82F6), // Blue
    Color(0xFFF59E0B), // Amber
    Color(0xFF8B5CF6), // Purple
    Color(0xFF10B981), // Emerald
    Color(0xFFEF4444), // Red
    Color(0xFFEC4899), // Pink
    Color(0xFF06B6D4), // Cyan
    Color(0xFF64748B), // Slate
  ];

  @override
  void dispose() {
    _newLaneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspaceState = ref.watch(activeWorkspaceProvider);
    final lanes = workspaceState.lanes;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 650),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.view_column_rounded, color: Color(0xFF6366F1)),
                    const SizedBox(width: 10),
                    Text(
                      'Manage Kanban Lanes',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Add custom columns, reorder, or update accent colors for your workspace.',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
            const Divider(height: 24),

            // Add New Lane Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newLaneController,
                    decoration: InputDecoration(
                      hintText: 'New lane name (e.g. In Review)',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.color_lens, color: _selectedColor),
                  tooltip: 'Select Color',
                  onPressed: _showColorPicker,
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    if (_newLaneController.text.trim().isNotEmpty) {
                      ref
                          .read(activeWorkspaceProvider.notifier)
                          .addLane(_newLaneController.text.trim(), _selectedColor);
                      _newLaneController.clear();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  icon: const Icon(Icons.add, size: 18, color: Colors.white),
                  label: const Text('Add Lane', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Existing Lanes Reorderable List
            Expanded(
              child: ReorderableListView.builder(
                itemCount: lanes.length,
                onReorderItem: (oldIndex, newIndex) {
                  ref.read(activeWorkspaceProvider.notifier).reorderLanes(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final lane = lanes[index];
                  return Card(
                    key: ValueKey(lane.id),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.drag_indicator, color: Colors.grey),
                          const SizedBox(width: 8),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: lane.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      title: Text(
                        lane.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: lane.isDefault
                          ? const Text('Default Column', style: TextStyle(fontSize: 11, color: Colors.grey))
                          : const Text('Custom Column', style: TextStyle(fontSize: 11, color: Color(0xFF6366F1))),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _showEditLaneDialog(lane),
                          ),
                          if (!lane.isDefault)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                              onPressed: () => _confirmDeleteLane(lane),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteLane(KanbanLane lane) async {
    final tasksInLane =
        ref.read(tasksProvider).where((t) => t.laneId == lane.id).toList();
    final otherLanes = ref
        .read(activeWorkspaceProvider)
        .lanes
        .where((l) => l.id != lane.id)
        .toList();

    if (tasksInLane.isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete "${lane.title}"?'),
          content: const Text('This lane will be removed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete Lane'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        ref.read(activeWorkspaceProvider.notifier).deleteLane(lane.id);
      }
      return;
    }

    if (otherLanes.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Cannot delete "${lane.title}"'),
          content: Text(
            'This lane contains ${tasksInLane.length} task(s). Create another lane '
            'and move the tasks there before deleting this one.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Tasks must be moved out before the lane can be deleted.
    var targetLane = otherLanes.first;
    final target = await showDialog<KanbanLane>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Delete "${lane.title}"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This lane still contains ${tasksInLane.length} task(s). '
                'Move them to another lane before deleting.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<KanbanLane>(
                initialValue: targetLane,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Move tasks to', isDense: true),
                items: otherLanes
                    .map((l) => DropdownMenuItem(value: l, child: Text(l.title)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => targetLane = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, targetLane),
              child: const Text('Move Tasks & Delete'),
            ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;

    for (final task in tasksInLane) {
      ref.read(tasksProvider.notifier).moveTaskLane(task.id, target.id);
    }
    ref.read(activeWorkspaceProvider.notifier).deleteLane(lane.id);
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick Column Color'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _presetColors.map((color) {
            return GestureDetector(
              onTap: () {
                setState(() => _selectedColor = color);
                Navigator.pop(ctx);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _selectedColor == color ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showEditLaneDialog(KanbanLane lane) {
    final editController = TextEditingController(text: lane.title);
    Color editColor = lane.color;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final name = editController.text.trim();
          final isEmpty = name.isEmpty;
          return AlertDialog(
            title: Text('Edit ${lane.title}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: editController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Column Title',
                    errorText: isEmpty ? 'Lane name cannot be empty' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Accent Color: '),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(color: editColor, shape: BoxShape.circle),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: isEmpty
                    ? null
                    : () {
                        ref
                            .read(activeWorkspaceProvider.notifier)
                            .updateLane(lane.id, name, editColor);
                        Navigator.pop(ctx);
                      },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}
