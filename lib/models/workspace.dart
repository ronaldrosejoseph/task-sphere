import 'lane.dart';

enum UserRole { admin, member }

class WorkspaceMember {
  final String id;
  final String workspaceId;
  final String? userId;
  final String email;
  final UserRole role;

  WorkspaceMember({
    required this.id,
    required this.workspaceId,
    this.userId,
    required this.email,
    required this.role,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workspace_id': workspaceId,
      'user_id': userId,
      'email': email,
      'role': role.name,
    };
  }

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    return WorkspaceMember(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      userId: json['user_id'] as String?,
      email: json['email'] as String? ?? 'member@example.com',
      role: json['role'].toString().toLowerCase() == 'admin' ? UserRole.admin : UserRole.member,
    );
  }
}

class Workspace {
  final String id;
  final String name;
  final String adminId;
  final int autoArchiveDays;
  final bool showArchivedTasks;
  final DateTime createdAt;
  final List<WorkspaceMember> members;

  /// The lanes whose tasks auto-hide after [autoArchiveDays]. Null means the
  /// admin has not configured this yet; [resolvedAutoExpiryLaneIds] then falls
  /// back to the lanes titled Done / Wont Do. An explicit empty list means
  /// auto-expiry is disabled.
  final List<String>? autoExpiryLaneIds;

  Workspace({
    required this.id,
    required this.name,
    required this.adminId,
    this.autoArchiveDays = 14,
    this.showArchivedTasks = false,
    this.autoExpiryLaneIds,
    DateTime? createdAt,
    this.members = const [],
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'admin_id': adminId,
      'auto_archive_days': autoArchiveDays,
      'show_archived_tasks': showArchivedTasks,
      'auto_expiry_lane_ids': autoExpiryLaneIds,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Workspace.fromJson(Map<String, dynamic> json, {List<WorkspaceMember>? members}) {
    return Workspace(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Default Workspace',
      adminId: json['admin_id'] as String? ?? '',
      autoArchiveDays: json['auto_archive_days'] as int? ?? 14,
      showArchivedTasks: json['show_archived_tasks'] as bool? ?? false,
      autoExpiryLaneIds: (json['auto_expiry_lane_ids'] as List?)?.cast<String>(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      members: members ?? [],
    );
  }

  Workspace copyWith({
    String? name,
    int? autoArchiveDays,
    bool? showArchivedTasks,
    List<String>? autoExpiryLaneIds,
    List<WorkspaceMember>? members,
  }) {
    return Workspace(
      id: id,
      name: name ?? this.name,
      adminId: adminId,
      autoArchiveDays: autoArchiveDays ?? this.autoArchiveDays,
      showArchivedTasks: showArchivedTasks ?? this.showArchivedTasks,
      autoExpiryLaneIds: autoExpiryLaneIds ?? this.autoExpiryLaneIds,
      createdAt: createdAt,
      members: members ?? this.members,
    );
  }

  /// The lanes eligible for auto-expiry: the stored selection when the admin
  /// saved one, otherwise the lanes titled Done / Wont Do (legacy behavior,
  /// so pre-existing workspaces keep working after a lane rename until the
  /// selection is configured in Settings).
  List<String> resolvedAutoExpiryLaneIds(List<KanbanLane> lanes) {
    final stored = autoExpiryLaneIds;
    if (stored != null) return stored;
    return [
      for (final lane in lanes)
        if (lane.title.toLowerCase() == 'done' ||
            lane.title.toLowerCase() == 'wont do')
          lane.id,
    ];
  }
}
