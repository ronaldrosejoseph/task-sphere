import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/lane.dart';
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
                onReorder: (oldIndex, newIndex) {
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
                              onPressed: () {
                                ref.read(activeWorkspaceProvider.notifier).deleteLane(lane.id);
                              },
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
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${lane.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: editController,
              decoration: const InputDecoration(labelText: 'Column Title'),
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
            onPressed: () {
              ref
                  .read(activeWorkspaceProvider.notifier)
                  .updateLane(lane.id, editController.text.trim(), editColor);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
