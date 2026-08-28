class ActivityLog {
  final String id;
  final String? taskId;
  final String workspaceId;
  final String userName;
  final String action;
  final DateTime createdAt;

  ActivityLog({
    required this.id,
    this.taskId,
    required this.workspaceId,
    required this.userName,
    required this.action,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task_id': taskId,
      'workspace_id': workspaceId,
      'user_name': userName,
      'action': action,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ActivityLog.fromJson(Map<String, dynamic> json) {
    return ActivityLog(
      id: json['id'] as String,
      taskId: json['task_id'] as String?,
      workspaceId: json['workspace_id'] as String,
      userName: json['user_name'] as String? ?? 'User',
      action: json['action'] as String? ?? 'performed action',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}
