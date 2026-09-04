import 'package:flutter/material.dart';
import 'subtask.dart';

enum TaskPriority { urgent, high, medium, low }

extension TaskPriorityExtension on TaskPriority {
  String get label {
    switch (this) {
      case TaskPriority.urgent:
        return 'Urgent';
      case TaskPriority.high:
        return 'High';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.low:
        return 'Low';
    }
  }

  Color get color {
    switch (this) {
      case TaskPriority.urgent:
        return const Color(0xFFEF4444);
      case TaskPriority.high:
        return const Color(0xFFF97316);
      case TaskPriority.medium:
        return const Color(0xFFF59E0B);
      case TaskPriority.low:
        return const Color(0xFF10B981);
    }
  }
}

/// Sorts tasks for board/list rendering: priority descending, then
/// soonest due date first, tasks without a due date last.
int compareTasksForBoard(TaskItem a, TaskItem b) {
  final priorityDelta = a.priority.index - b.priority.index;
  if (priorityDelta != 0) return priorityDelta;
  final aDue = a.dueDate;
  final bDue = b.dueDate;
  if (aDue == null && bDue == null) return 0;
  if (aDue == null) return 1;
  if (bDue == null) return -1;
  return aDue.compareTo(bDue);
}

class TaskItem {
  final String id;
  final String workspaceId;
  final String laneId;
  final String title;
  final String description;
  final String? assigneeId;
  final String? assigneeEmail;
  final String? assigneeName;
  final TaskPriority priority;
  final DateTime? dueDate;
  final double estimatedHours;
  final int loggedSeconds;
  final List<String> attachmentPaths;
  final bool isArchived;
  final List<Subtask> subtasks;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  TaskItem({
    required this.id,
    required this.workspaceId,
    required this.laneId,
    required this.title,
    this.description = '',
    this.assigneeId,
    this.assigneeEmail,
    this.assigneeName,
    this.priority = TaskPriority.medium,
    this.dueDate,
    this.estimatedHours = 0.0,
    this.loggedSeconds = 0,
    this.attachmentPaths = const [],
    this.isArchived = false,
    this.subtasks = const [],
    this.createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get subtasksProgress {
    if (subtasks.isEmpty) return 0.0;
    final completedCount = subtasks.where((s) => s.isCompleted).length;
    return completedCount / subtasks.length;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workspace_id': workspaceId,
      'lane_id': laneId,
      'title': title,
      'description': description,
      'assignee_id': assigneeId,
      'assignee_email': assigneeEmail,
      'assignee_name': assigneeName,
      'priority': priority.name,
      'due_date': dueDate?.toIso8601String(),
      'estimated_hours': estimatedHours,
      'logged_seconds': loggedSeconds,
      'attachment_paths': attachmentPaths,
      'is_archived': isArchived,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory TaskItem.fromJson(Map<String, dynamic> json, {List<Subtask>? subtasks}) {
    TaskPriority p = TaskPriority.medium;
    if (json['priority'] != null) {
      p = TaskPriority.values.firstWhere(
        (e) => e.name == json['priority'].toString().toLowerCase(),
        orElse: () => TaskPriority.medium,
      );
    }

    return TaskItem(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      laneId: json['lane_id'] as String,
      title: json['title'] as String? ?? 'Untitled Task',
      description: json['description'] as String? ?? '',
      assigneeId: json['assignee_id'] as String?,
      assigneeEmail: json['assignee_email'] as String?,
      assigneeName: json['assignee_name'] as String?,
      priority: p,
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
      estimatedHours: (json['estimated_hours'] as num?)?.toDouble() ?? 0.0,
      loggedSeconds: json['logged_seconds'] as int? ?? 0,
      attachmentPaths: (json['attachment_paths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isArchived: json['is_archived'] as bool? ?? false,
      subtasks: subtasks ?? [],
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  // Sentinel default for the clearable assignee fields: an omitted
  // parameter keeps the current value, while an explicit null (the
  // 'Unassigned' choice) clears it. A plain `?? this.x` can never unassign.
  static const Object _unset = Object();

  TaskItem copyWith({
    String? laneId,
    String? title,
    String? description,
    Object? assigneeId = _unset,
    Object? assigneeEmail = _unset,
    Object? assigneeName = _unset,
    TaskPriority? priority,
    DateTime? dueDate,
    double? estimatedHours,
    int? loggedSeconds,
    List<String>? attachmentPaths,
    bool? isArchived,
    List<Subtask>? subtasks,
  }) {
    return TaskItem(
      id: id,
      workspaceId: workspaceId,
      laneId: laneId ?? this.laneId,
      title: title ?? this.title,
      description: description ?? this.description,
      assigneeId: assigneeId == _unset ? this.assigneeId : assigneeId as String?,
      assigneeEmail: assigneeEmail == _unset
          ? this.assigneeEmail
          : assigneeEmail as String?,
      assigneeName: assigneeName == _unset ? this.assigneeName : assigneeName as String?,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      estimatedHours: estimatedHours ?? this.estimatedHours,
      loggedSeconds: loggedSeconds ?? this.loggedSeconds,
      attachmentPaths: attachmentPaths ?? this.attachmentPaths,
      isArchived: isArchived ?? this.isArchived,
      subtasks: subtasks ?? this.subtasks,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
