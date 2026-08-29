import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/task.dart';
import '../../models/subtask.dart';
import '../../providers/task_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/services/storage_service.dart';

const _uuid = Uuid();

class TaskDetailModal extends ConsumerStatefulWidget {
  final TaskItem? task;
  final String? initialLaneId;

  const TaskDetailModal({super.key, this.task, this.initialLaneId});

  @override
  ConsumerState<TaskDetailModal> createState() => _TaskDetailModalState();
}

class _TaskDetailModalState extends ConsumerState<TaskDetailModal> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _newSubtaskController;

  late String _selectedLaneId;
  late TaskPriority _selectedPriority;
  String? _assigneeEmail;
  String? _assigneeName;
  DateTime? _dueDate;
  double _estimatedHours = 0.0;
  List<Subtask> _subtasks = [];
  List<String> _attachmentPaths = [];
  late final String _newTaskId;

  // Stopwatch state
  bool _isTimerRunning = false;
  int _sessionSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final lanes = ref.read(activeWorkspaceProvider).lanes;
    _selectedLaneId = widget.task?.laneId ?? widget.initialLaneId ?? (lanes.isNotEmpty ? lanes.first.id : '');

    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _descController = TextEditingController(text: widget.task?.description ?? '');
    _newSubtaskController = TextEditingController();

    _selectedPriority = widget.task?.priority ?? TaskPriority.medium;
    _assigneeEmail = widget.task?.assigneeEmail;
    _assigneeName = widget.task?.assigneeName;
    _dueDate = widget.task?.dueDate;
    _estimatedHours = widget.task?.estimatedHours ?? 0.0;
    _subtasks = List.from(widget.task?.subtasks ?? []);
    _attachmentPaths = List.from(widget.task?.attachmentPaths ?? []);
    _newTaskId = widget.task?.id ?? _uuid.v4();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _titleController.dispose();
    _descController.dispose();
    _newSubtaskController.dispose();
    super.dispose();
  }

  void _toggleTimer() {
    if (_isTimerRunning) {
      _timer?.cancel();
      setState(() => _isTimerRunning = false);
    } else {
      setState(() => _isTimerRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _sessionSeconds += 1);
      });
    }
  }

  String _formatSeconds(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final workspaceState = ref.watch(activeWorkspaceProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
        child: Column(
          children: [
            // Modal Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _selectedPriority.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.assignment, color: _selectedPriority.color),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      widget.task == null ? 'Create New Task' : 'Task Details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (widget.task != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        tooltip: 'Delete Task',
                        onPressed: () {
                          ref.read(tasksProvider.notifier).deleteTask(widget.task!.id);
                          Navigator.pop(context);
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                )
              ],
            ),
            const Divider(height: 24),

            // Scrollable Editor Body
            Expanded(
              child: ListView(
                children: [
                  // Title Input
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: 'Task Title...',
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Metadata Grid (Lane, Priority, Assignee, Due Date)
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      // Lane Dropdown
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedLaneId.isNotEmpty ? _selectedLaneId : null,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Kanban Lane', isDense: true),
                          items: workspaceState.lanes.map((lane) {
                            return DropdownMenuItem(
                              value: lane.id,
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(color: lane.color, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      lane.title,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedLaneId = val);
                          },
                        ),
                      ),

                      // Priority Dropdown
                      SizedBox(
                        width: 160,
                        child: DropdownButtonFormField<TaskPriority>(
                          initialValue: _selectedPriority,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Priority', isDense: true),
                          items: TaskPriority.values.map((p) {
                            return DropdownMenuItem(
                              value: p,
                              child: Row(
                                children: [
                                  Icon(Icons.circle, size: 10, color: p.color),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      p.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedPriority = val);
                          },
                        ),
                      ),

                      // Assignee Dropdown
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          initialValue: _assigneeEmail,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Assignee', isDense: true),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Unassigned')),
                            ...workspaceState.activeWorkspace.members.map((m) {
                              return DropdownMenuItem(
                                value: m.email,
                                child: Text(
                                  '${m.email.split("@").first} (${m.role.name})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _assigneeEmail = val;
                              _assigneeName = val?.split('@').first;
                            });
                          },
                        ),
                      ),

                      // Due Date Picker
                      InkWell(
                        onTap: _pickDueDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today, size: 16, color: Color(0xFF6366F1)),
                              const SizedBox(width: 8),
                              Text(
                                _dueDate == null
                                    ? 'Set Due Date'
                                    : DateFormat('MMM dd, yyyy').format(_dueDate!),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Description Input
                  const Text('Description', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _descController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Add details, context, or requirements...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Stopwatch & Time Tracker
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.timer_outlined, color: Colors.blueAccent),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Time Tracker', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(
                                  'Total Logged: ${_formatSeconds((widget.task?.loggedSeconds ?? 0) + _sessionSeconds)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: _toggleTimer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isTimerRunning ? Colors.redAccent : Colors.blueAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(_isTimerRunning ? Icons.pause : Icons.play_arrow, color: Colors.white),
                          label: Text(
                            _isTimerRunning ? 'Pause (${_formatSeconds(_sessionSeconds)})' : 'Start Timer',
                            style: const TextStyle(color: Colors.white),
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Checklist Subtasks Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtasks Checklist', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${_subtasks.where((s) => s.isCompleted).length}/${_subtasks.length} Completed',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: _subtasks.isEmpty ? 0 : _subtasks.where((s) => s.isCompleted).length / _subtasks.length,
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 10),

                  ..._subtasks.map((st) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Checkbox(
                        value: st.isCompleted,
                        onChanged: (val) {
                          setState(() {
                            final idx = _subtasks.indexWhere((element) => element.id == st.id);
                            if (idx != -1) {
                              _subtasks[idx] = st.copyWith(isCompleted: val ?? false);
                            }
                          });
                        },
                      ),
                      title: Text(
                        st.title,
                        style: TextStyle(
                          decoration: st.isCompleted ? TextDecoration.lineThrough : null,
                          color: st.isCompleted ? Colors.grey : null,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                        onPressed: () {
                          setState(() => _subtasks.removeWhere((element) => element.id == st.id));
                        },
                      ),
                    );
                  }),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newSubtaskController,
                          decoration: const InputDecoration(
                            hintText: 'Add a subtask item...',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addSubtask(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Color(0xFF6366F1)),
                        onPressed: _addSubtask,
                      )
                    ],
                  ),
                  const SizedBox(height: 20),

                  // File Attachments (Supabase Storage)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Attachments', style: TextStyle(fontWeight: FontWeight.w600)),
                      TextButton.icon(
                        onPressed: _pickAndUploadAttachment,
                        icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: const Text('Upload File'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_attachmentPaths.isEmpty)
                    Text('No files attached yet.', style: TextStyle(fontSize: 12, color: Colors.grey[400]))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _attachmentPaths.map((path) {
                        return InputChip(
                          avatar: const Icon(Icons.insert_drive_file, size: 16, color: Color(0xFF3B82F6)),
                          label: Text(path.split('/').last),
                          onPressed: () => _openAttachment(path),
                          onDeleted: () => _removeAttachment(path),
                          deleteIcon: const Icon(Icons.close, size: 14),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            const Divider(height: 20),

            // Save Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _saveTask,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  icon: const Icon(Icons.save, color: Colors.white, size: 18),
                  label: const Text('Save Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  void _addSubtask() {
    final text = _newSubtaskController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _subtasks.add(Subtask(
          id: _uuid.v4(),
          taskId: widget.task?.id ?? 'temp',
          title: text,
        ));
        _newSubtaskController.clear();
      });
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _pickAndUploadAttachment() async {
    if (!SupabaseStorageService.instance.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attachments require a connected Supabase project.'),
        ),
      );
      return;
    }

    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;

    final file = files.first;
    final bytes = await file.readAsBytes();
    final workspaceId = ref.read(activeWorkspaceProvider).activeWorkspace.id;
    final path = await SupabaseStorageService.instance.uploadAttachment(
      workspaceId: workspaceId,
      taskId: _newTaskId,
      fileName: file.name,
      fileBytes: bytes,
      mimeType: 'application/octet-stream',
    );
    if (path != null && mounted) {
      setState(() => _attachmentPaths.add(path));
    }
  }

  Future<void> _openAttachment(String path) async {
    final url = await SupabaseStorageService.instance.createSignedUrl(path);
    if (url != null && mounted) {
      await launchUrl(Uri.parse(url));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open attachment.')),
      );
    }
  }

  Future<void> _removeAttachment(String path) async {
    setState(() => _attachmentPaths.remove(path));
    await SupabaseStorageService.instance.deleteAttachment(path);
  }

  void _saveTask() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    if (widget.task == null && ref.read(isDemoUserProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Creating tasks is disabled in the demo.')),
      );
      return;
    }

    final ws = ref.read(activeWorkspaceProvider).activeWorkspace;
    if (ws.id.isEmpty || ws.id == 'loading') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a workspace before adding tasks.')),
      );
      return;
    }
    final wsId = ws.id;

    final currentUser = ref.read(authProvider);

    if (widget.task == null) {
      // Create New Task
      final taskId = _newTaskId;
      final newTask = TaskItem(
        id: taskId,
        workspaceId: wsId,
        laneId: _selectedLaneId,
        title: title,
        description: _descController.text.trim(),
        assigneeEmail: _assigneeEmail,
        assigneeName: _assigneeName,
        priority: _selectedPriority,
        dueDate: _dueDate,
        estimatedHours: _estimatedHours,
        loggedSeconds: _sessionSeconds,
        subtasks: [
          for (final subtask in _subtasks) subtask.copyWith(taskId: taskId),
        ],
        attachmentPaths: _attachmentPaths,
        createdBy: currentUser?.displayName ?? 'Admin',
      );
      ref.read(tasksProvider.notifier).addTask(newTask);
      ref.read(activityLogsProvider.notifier).addLog(
            wsId,
            currentUser?.displayName ?? 'Admin',
            'Created task "$title"',
            taskId: newTask.id,
          );
    } else {
      // Update Existing Task
      final updated = widget.task!.copyWith(
        laneId: _selectedLaneId,
        title: title,
        description: _descController.text.trim(),
        assigneeEmail: _assigneeEmail,
        assigneeName: _assigneeName,
        priority: _selectedPriority,
        dueDate: _dueDate,
        estimatedHours: _estimatedHours,
        loggedSeconds: widget.task!.loggedSeconds + _sessionSeconds,
        subtasks: _subtasks,
        attachmentPaths: _attachmentPaths,
      );
      ref.read(tasksProvider.notifier).updateTask(updated);
      ref.read(activityLogsProvider.notifier).addLog(
            wsId,
            currentUser?.displayName ?? 'Admin',
            'Updated task "$title"',
            taskId: updated.id,
          );
    }

    Navigator.pop(context);
  }
}
