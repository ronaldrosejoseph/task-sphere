class TaskComment {
  final String id;
  final String taskId;
  final String workspaceId;
  final String? userId;
  final String displayName;
  final String body;
  final DateTime createdAt;

  TaskComment({
    required this.id,
    required this.taskId,
    required this.workspaceId,
    this.userId,
    required this.displayName,
    required this.body,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task_id': taskId,
      'workspace_id': workspaceId,
      'user_id': userId,
      'display_name': displayName,
      'body': body,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory TaskComment.fromJson(Map<String, dynamic> json) {
    return TaskComment(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      workspaceId: json['workspace_id'] as String,
      userId: json['user_id'] as String?,
      displayName: json['display_name'] as String? ?? 'User',
      body: json['body'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}
