class Subtask {
  final String id;
  final String taskId;
  final String title;
  final bool isCompleted;
  final int orderIndex;

  Subtask({
    required this.id,
    required this.taskId,
    required this.title,
    this.isCompleted = false,
    this.orderIndex = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task_id': taskId,
      'title': title,
      'is_completed': isCompleted,
      'order_index': orderIndex,
    };
  }

  factory Subtask.fromJson(Map<String, dynamic> json) {
    return Subtask(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      title: json['title'] as String,
      isCompleted: json['is_completed'] as bool? ?? false,
      orderIndex: json['order_index'] as int? ?? 0,
    );
  }

  Subtask copyWith({
    String? taskId,
    String? title,
    bool? isCompleted,
    int? orderIndex,
  }) {
    return Subtask(
      id: id,
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }
}
