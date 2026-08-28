import 'package:flutter/material.dart';

class KanbanLane {
  final String id;
  final String workspaceId;
  final String title;
  final String colorHex;
  final int orderIndex;
  final bool isDefault;

  KanbanLane({
    required this.id,
    required this.workspaceId,
    required this.title,
    this.colorHex = '#6366F1',
    this.orderIndex = 0,
    this.isDefault = false,
  });

  Color get color {
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF6366F1);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workspace_id': workspaceId,
      'title': title,
      'color_hex': colorHex,
      'order_index': orderIndex,
      'is_default': isDefault,
    };
  }

  factory KanbanLane.fromJson(Map<String, dynamic> json) {
    return KanbanLane(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      title: json['title'] as String,
      colorHex: json['color_hex'] as String? ?? '#6366F1',
      orderIndex: json['order_index'] as int? ?? 0,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  KanbanLane copyWith({
    String? title,
    String? colorHex,
    int? orderIndex,
    bool? isDefault,
  }) {
    return KanbanLane(
      id: id,
      workspaceId: workspaceId,
      title: title ?? this.title,
      colorHex: colorHex ?? this.colorHex,
      orderIndex: orderIndex ?? this.orderIndex,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
