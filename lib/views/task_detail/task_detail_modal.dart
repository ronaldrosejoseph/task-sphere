import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/task.dart';
import '../../models/subtask.dart';
import '../../models/task_comment.dart';
import '../../models/activity_log.dart';
import '../../models/workspace.dart';
import '../../providers/task_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/services/storage_service.dart';

const _uuid = Uuid();

class TaskDetailModal extends ConsumerStatefulWidget {
  final TaskItem? task;
  final String? initialLaneId;

  const TaskDetailModal({super.key, this.task, this.initialLaneId});

  /// Uploads are restricted to raster image formats. The picker is filtered
  /// to images and this guard catches pickers that can bypass the filter.
  static bool isAllowedImageFileName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1) return false;
    final ext = name.substring(dot + 1).toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp'}
        .contains(ext);
  }

  @override
  ConsumerState<TaskDetailModal> createState() => _TaskDetailModalState();
}

class _TaskDetailModalState extends ConsumerState<TaskDetailModal> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _newSubtaskController;
  late TextEditingController _commentController;

  late String _selectedLaneId;
  late TaskPriority _selectedPriority;
  String? _assigneeEmail;
  String? _assigneeName;
  DateTime? _dueDate;
  double _estimatedHours = 0.0;
  List<Subtask> _subtasks = [];
  List<String> _attachmentPaths = [];
  late final String _newTaskId;

  // The running session lives in runningTimersProvider so it survives modal
  // close; this ticker only redraws the elapsed time each second.
  Timer? _ticker;

  String get _timerTaskId => widget.task?.id ?? _newTaskId;

  @override
  void initState() {
    super.initState();
    final lanes = [...ref.read(activeWorkspaceProvider).lanes]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    _selectedLaneId = widget.task?.laneId ?? widget.initialLaneId ?? (lanes.isNotEmpty ? lanes.first.id : '');

    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _descController = TextEditingController(text: widget.task?.description ?? '');
    _newSubtaskController = TextEditingController();
    _commentController = TextEditingController();

    _selectedPriority = widget.task?.priority ?? TaskPriority.medium;
    _assigneeEmail = widget.task?.assigneeEmail;
    _assigneeName = widget.task?.assigneeName;
    _dueDate = widget.task?.dueDate;
    _estimatedHours = widget.task?.estimatedHours ?? 0.0;
    _subtasks = List.from(widget.task?.subtasks ?? []);
    _attachmentPaths = List.from(widget.task?.attachmentPaths ?? []);
    _newTaskId = widget.task?.id ?? _uuid.v4();
    _startTickerIfRunning();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _titleController.dispose();
    _descController.dispose();
    _newSubtaskController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _startTickerIfRunning() {
    if (_ticker != null) return;
    if (!ref.read(runningTimersProvider).containsKey(_timerTaskId)) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
    });
  }

  Widget _buildLaneField(WorkspaceState workspaceState) {
    return DropdownButtonFormField<String>(
      initialValue: _selectedLaneId.isNotEmpty ? _selectedLaneId : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Kanban Lane', isDense: true),
      items: ([...workspaceState.lanes]
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)))
          .map((lane) {
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
    );
  }

  Widget _buildPriorityField() {
    return DropdownButtonFormField<TaskPriority>(
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
    );
  }

  Widget _buildAssigneeField(WorkspaceState workspaceState) {
    return DropdownButtonFormField<String>(
      initialValue: _assigneeEmail,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Assignee', isDense: true),
      items: [
        const DropdownMenuItem(value: null, child: Text('Unassigned')),
        ...workspaceState.activeWorkspace.members.map((m) {
          return DropdownMenuItem(
            value: m.email,
            child: Text(
              m.displayLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ],
      onChanged: (val) {
        setState(() {
          _assigneeEmail = val;
          // Snapshot the display label on the task so the card keeps a name
          // even if the member leaves.
          _assigneeName = val == null
              ? null
              : memberDisplayLabel(
                      workspaceState.activeWorkspace.members,
                      val,
                    ) ??
                  val.split('@').first;
        });
      },
    );
  }

  /// The created (read-only) and due dates share one bordered container,
  /// divided so each half reads as its own field.
  Widget _buildDatesContainer() {
    final hasCreated = widget.task != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (hasCreated) ...[
            Expanded(
              child: _dateCell(
                icon: Icons.calendar_today,
                label: 'Created',
                value: DateFormat('MMM dd, yyyy').format(widget.task!.createdAt),
              ),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 34, color: Colors.grey.withValues(alpha: 0.3)),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: _dateCell(
              icon: Icons.schedule,
              label: 'Due Date',
              value: _dueDate == null
                  ? 'Set Due Date'
                  : DateFormat('MMM dd, yyyy').format(_dueDate!),
              onTap: _pickDueDate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateCell({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF6366F1)),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: onTap != null ? const Color(0xFF6366F1) : null,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: content,
    );
  }

  void _toggleTimer() {
    final notifier = ref.read(runningTimersProvider.notifier);
    if (notifier.isRunning(_timerTaskId)) {
      notifier.pause(_timerTaskId);
    } else {
      notifier.start(_timerTaskId);
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
    // Riverpod 3 requires listen inside build; starts/stops the elapsed-time
    // ticker when the running session for this task starts or stops.
    ref.listen(runningTimersProvider, (_, next) {
      if (next.containsKey(_timerTaskId)) {
        _startTickerIfRunning();
      } else {
        _ticker?.cancel();
        _ticker = null;
      }
    });
    final workspaceState = ref.watch(activeWorkspaceProvider);
    final currentUser = ref.read(authProvider);
    final isAdmin = ref.read(activeWorkspaceProvider.notifier).isAdmin(currentUser);
    final isOwnTicket = widget.task != null &&
        widget.task!.createdBy != null &&
        widget.task!.createdBy == currentUser?.id;
    // Members can edit the title/description only on tickets they created;
    // admins can edit everything. Other fields stay editable for everyone.
    final canEditTitleDescription = isAdmin || widget.task == null || isOwnTicket;
    final canDeleteTask = isAdmin && widget.task != null;
    final comments = widget.task == null
        ? null
        : ref.watch(taskCommentsProvider(widget.task!.id));
    // Per-ticket activity entries, newest first (addLog prepends and the
    // repository returns logs newest-first).
    final taskLogs = widget.task == null
        ? null
        : ref
            .watch(activityLogsProvider)
            .where((log) => log.taskId == widget.task!.id)
            .toList();

    // On phones the default 40px dialog insets squeeze the modal to ~280px
    // wide; shrink the insets so it fills the screen instead.
    final screenSize = MediaQuery.sizeOf(context);
    final isNarrow = screenSize.width < 600;
    // Phones and tablets stack the metadata fields full-width; the compact
    // grid only fits on wide desktops where the dialog has room to breathe.
    final stackMetadata = screenSize.width < 1100;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 16 : 40,
        vertical: isNarrow ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: BoxConstraints(
          maxWidth: isNarrow ? screenSize.width - 32 : 700,
          maxHeight: isNarrow ? screenSize.height - 32 : 800,
        ),
        child: Column(
          children: [
            // Modal Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
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
                      Flexible(
                        child: Text(
                          widget.task == null ? 'Create New Task' : 'Task Details',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    if (canDeleteTask)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        tooltip: 'Delete Task',
                        onPressed: _confirmDeleteTask,
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
                    readOnly: !canEditTitleDescription,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: 'Task Title...',
                      border: InputBorder.none,
                    ),
                  ),
                  if (!canEditTitleDescription)
                    Text(
                      'Only the creator or an admin can edit the title and description.',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[500],
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Metadata Grid (Lane, Priority, Assignee, Dates)
                  //
                  // Phones and tablets stack the three dropdowns and the
                  // dates container full-width; wide desktops keep the
                  // compact side-by-side grid.
                  if (stackMetadata)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildLaneField(workspaceState),
                        const SizedBox(height: 14),
                        _buildPriorityField(),
                        const SizedBox(height: 14),
                        _buildAssigneeField(workspaceState),
                        const SizedBox(height: 14),
                        _buildDatesContainer(),
                      ],
                    )
                  else
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.start,
                      children: [
                        SizedBox(width: 200, child: _buildLaneField(workspaceState)),
                        SizedBox(width: 160, child: _buildPriorityField()),
                        SizedBox(width: 220, child: _buildAssigneeField(workspaceState)),
                        SizedBox(width: 300, child: _buildDatesContainer()),
                      ],
                    ),
                  const SizedBox(height: 20),

                  // Description Input
                  const Text('Description', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _descController,
                    // Always grow with the content so the full description is
                    // readable without expansion controls; the modal scrolls.
                    minLines: 3,
                    maxLines: null,
                    readOnly: !canEditTitleDescription,
                    decoration: InputDecoration(
                      hintText: 'Add details, context, or requirements...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Stopwatch & Time Tracker
                  Builder(builder: (context) {
                    final running = ref.watch(runningTimersProvider).containsKey(_timerTaskId);
                    final elapsed =
                        ref.read(runningTimersProvider.notifier).elapsedSeconds(_timerTaskId);
                    final totalLogged = (widget.task?.loggedSeconds ?? 0) + elapsed;
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                      ),
                      // Wraps so the Start Timer button drops to its own line
                      // on narrow phone screens instead of overflowing.
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, color: Colors.blueAccent),
                              const SizedBox(width: 10),
                              // Fixed width: the seconds string grows every
                              // tick, which used to widen this row and push
                              // the Pause button around until it wrapped.
                              SizedBox(
                                width: 170,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Time Tracker', style: TextStyle(fontWeight: FontWeight.bold)),
                                    Text(
                                      'Total Logged: ${_formatSeconds(totalLogged)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: _toggleTimer,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: running ? Colors.redAccent : Colors.blueAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: Icon(running ? Icons.pause : Icons.play_arrow, color: Colors.white),
                            label: Text(
                              running ? 'Pause' : 'Start Timer',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 20),

                  // Checklist Subtasks Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Subtasks Checklist',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                      Flexible(
                        child: Text(
                          'Attachments',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                  const SizedBox(height: 20),

                  // Comments Thread
                  if (widget.task != null && comments != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Comments', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          '${comments.length}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (comments.isEmpty)
                      Text(
                        'No comments yet. Start the discussion!',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      )
                    else
                      for (final comment in comments)
                        _buildCommentTile(comment, currentUserId: currentUser?.id, isAdmin: isAdmin),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            decoration: InputDecoration(
                              hintText: 'Add a comment...',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onSubmitted: (_) => _addComment(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.send, size: 18),
                          onPressed: _addComment,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Activity feed: who moved this ticket, checked off a
                  // subtask, or attached a file — plus create/update entries.
                  if (widget.task != null && taskLogs != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Activity', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          '${taskLogs.length}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (taskLogs.isEmpty)
                      Text(
                        'No activity yet.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      )
                    else
                      for (final log in taskLogs)
                        _buildActivityTile(log),
                  ],
                ],
              ),
            ),
            const Divider(height: 20),

            // Save Actions
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 12,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: _saveTask,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  icon: const Icon(Icons.save, color: Colors.white, size: 18),
                  label: const Text('Save Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
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

  void _addComment() {
    final text = _commentController.text.trim();
    if (text.isEmpty || widget.task == null) return;
    ref.read(taskCommentsProvider(widget.task!.id).notifier).addComment(text);
    _commentController.clear();
  }

  Widget _buildCommentTile(
    TaskComment comment, {
    required String? currentUserId,
    required bool isAdmin,
  }) {
    final canDelete =
        isAdmin || (comment.userId != null && comment.userId == currentUserId);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
            child: Text(
              comment.displayName.isNotEmpty ? comment.displayName[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6366F1),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.displayName,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        DateFormat('MMM d, HH:mm').format(comment.createdAt.toLocal()),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.body, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
              tooltip: 'Delete Comment',
              onPressed: () => ref
                  .read(taskCommentsProvider(widget.task!.id).notifier)
                  .removeComment(comment.id),
            ),
        ],
      ),
    );
  }

  Widget _buildActivityTile(ActivityLog log) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
            child: Text(
              log.displayName.isNotEmpty ? log.displayName[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF6366F1),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        log.displayName,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        DateFormat('MMM d, HH:mm').format(log.createdAt.toLocal()),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(log.action, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteTask() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this task?'),
        content: const Text(
          'This permanently deletes the task along with its comments, '
          'subtasks, and attached files. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ref.read(tasksProvider.notifier).deleteTask(widget.task!.id);
      Navigator.pop(context);
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
      _showUploadError('Attachments require a connected Supabase project.');
      return;
    }

    final List<PlatformFile> files;
    try {
      // pickFiles multi-selects by default (file_picker 12); every image the
      // user chose is uploaded below.
      files = await FilePicker.pickFiles(type: FileType.image);
    } catch (e) {
      _showUploadError('Could not open the file picker: $e');
      return;
    }
    // The user cancelled the picker.
    if (files.isEmpty) return;

    var failures = 0;
    for (final file in files) {
      if (!await _uploadAttachment(file)) {
        failures++;
      }
    }
    if (failures > 0 && mounted) {
      final message = failures == files.length
          ? 'Upload failed. Check your connection and try again.'
          : '$failures of ${files.length} images failed to upload.';
      _showUploadError(message);
    }
  }

  /// Uploads one picked image; returns false when the file is invalid or the
  /// upload fails (the specific failure is debugPrinted by the storage
  /// service, and skipped files are reported by the caller as a count).
  Future<bool> _uploadAttachment(PlatformFile file) async {
    // iOS Safari photo picks can come through with an empty name; storage
    // keys must end in a usable filename.
    final fileName = file.name.trim().isEmpty ? 'attachment.jpg' : file.name;
    if (!TaskDetailModal.isAllowedImageFileName(fileName)) {
      return false;
    }

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      return false;
    }
    if (bytes.isEmpty) {
      return false;
    }

    final workspaceId = ref.read(activeWorkspaceProvider).activeWorkspace.id;
    final path = await SupabaseStorageService.instance.uploadAttachment(
      workspaceId: workspaceId,
      taskId: _newTaskId,
      fileName: fileName,
      fileBytes: bytes,
      mimeType: 'application/octet-stream',
    );
    if (path == null) {
      // uploadAttachment already debugPrints the underlying error.
      return false;
    }
    if (mounted) {
      setState(() => _attachmentPaths.add(path));
    }
    return true;
  }

  void _showUploadError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _saveTask() async {
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
    // The actor label prefers the admin-set member display name and falls
    // back to the Google/account name; email prefixes never reach the feed.
    final actor = memberDisplayName(ws.members, currentUser?.email) ??
        currentUser?.displayName ??
        'Admin';

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
        loggedSeconds: 0,
        subtasks: [
          for (final subtask in _subtasks) subtask.copyWith(taskId: taskId),
        ],
        attachmentPaths: _attachmentPaths,
        // The column is UUID REFERENCES auth.users(id); a display name
        // string would fail the INSERT.
        createdBy: currentUser?.id,
      );
      // Await the task insert so the activity log (whose task_id references
      // the tasks row) can never reach the database first and fail the FK.
      await ref.read(tasksProvider.notifier).addTask(newTask);
      ref.read(activityLogsProvider.notifier).addLog(
            wsId,
            actor,
            'Created task "$title"',
            taskId: newTask.id,
          );
    } else {
      // Update Existing Task. The save is diffed against the task as it was
      // when the modal opened: each field change becomes its own feed entry,
      // and a no-op save persists nothing and logs nothing.
      final original = widget.task!;
      final updated = original.copyWith(
        laneId: _selectedLaneId,
        title: title,
        description: _descController.text.trim(),
        assigneeEmail: _assigneeEmail,
        assigneeName: _assigneeName,
        priority: _selectedPriority,
        dueDate: _dueDate,
        estimatedHours: _estimatedHours,
        subtasks: _subtasks,
        attachmentPaths: _attachmentPaths,
      );
      final wsState = ref.read(activeWorkspaceProvider);
      final laneTitles = {for (final l in wsState.lanes) l.id: l.title};
      final actions = <String>[];

      if (updated.laneId != original.laneId) {
        actions.add('Moved from ${laneTitles[original.laneId] ?? 'another lane'} '
            'to ${laneTitles[updated.laneId] ?? 'another lane'}');
      }
      if (updated.priority != original.priority) {
        actions.add('Changed priority from ${original.priority.label} '
            'to ${updated.priority.label}');
      }
      if (updated.assigneeEmail != original.assigneeEmail) {
        final members = wsState.activeWorkspace.members;
        final oldAssignee = memberDisplayLabel(members, original.assigneeEmail) ??
            original.assigneeName ??
            'Unassigned';
        final newAssignee = memberDisplayLabel(members, updated.assigneeEmail) ??
            _assigneeName ??
            'Unassigned';
        actions.add('Changed assignee from $oldAssignee to $newAssignee');
      }

      // Description edits.
      final originalDesc = original.description;
      final newDesc = updated.description;
      if (originalDesc != newDesc) {
        if (newDesc.isEmpty) {
          actions.add('Removed description');
        } else if (originalDesc.isEmpty) {
          actions.add('Added description');
        } else {
          actions.add('Changed description');
        }
      }
      // Due date edits.
      if (updated.dueDate != original.dueDate) {
        String fmtDate(DateTime? d) =>
            d == null ? 'None' : DateFormat('MMM dd, yyyy').format(d);
        actions.add('Changed due date from ${fmtDate(original.dueDate)} '
            'to ${fmtDate(updated.dueDate)}');
      }
      // Subtask additions and removals since the modal opened.
      final originalSubtaskIds = {for (final st in original.subtasks) st.id};
      final currentSubtaskIds = {for (final st in _subtasks) st.id};
      for (final st in original.subtasks) {
        if (!currentSubtaskIds.contains(st.id)) {
          actions.add('Removed subtask "${st.title}"');
        }
      }
      for (final st in _subtasks) {
        if (!originalSubtaskIds.contains(st.id)) {
          actions.add('Added subtask "${st.title}"');
          // A brand-new subtask can be ticked before the save; the flip
          // diff below only sees subtasks that existed when the modal
          // opened, so the check is attributed here.
          if (st.isCompleted) {
            actions.add('Checked subtask "${st.title}"');
          }
        }
      }
      // Subtask check/uncheck flips since the modal opened.
      final beforeBySubtaskId = {for (final st in original.subtasks) st.id: st};
      for (final after in _subtasks) {
        final before = beforeBySubtaskId[after.id];
        if (before != null && before.isCompleted != after.isCompleted) {
          actions.add(after.isCompleted
              ? 'Checked subtask "${before.title}"'
              : 'Unchecked subtask "${before.title}"');
        }
      }
      // Newly attached files since the modal opened.
      for (final path in _attachmentPaths) {
        if (!original.attachmentPaths.contains(path)) {
          actions.add('Added attachment "${path.split('/').last}"');
        }
      }
      // Title edits, estimate changes, and attachment removals share one
      // generic entry so no change is lost.
      final otherChanged = updated.title != original.title ||
          updated.estimatedHours != original.estimatedHours ||
          !original.attachmentPaths.every(_attachmentPaths.contains);
      if (otherChanged) {
        actions.add('Updated task "$title"');
      }

      if (actions.isEmpty) {
        // Nothing changed; leave the row and the feed untouched.
        if (mounted) Navigator.pop(context);
        return;
      }

      ref.read(tasksProvider.notifier).updateTask(updated);
      final logNotifier = ref.read(activityLogsProvider.notifier);
      for (final action in actions) {
        logNotifier.addLog(wsId, actor, action, taskId: updated.id);
      }
    }

    // The create path above awaits the task insert, so the modal may have
    // been dismissed mid-flight.
    if (mounted) Navigator.pop(context);
  }
}
