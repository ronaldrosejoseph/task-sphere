enum UserRole { admin, member }

class WorkspaceMember {
  final String id;
  final String workspaceId;
  final String? userId;
  final String email;
  final UserRole role;

  /// Optional friendly name configured by the workspace admin; null falls
  /// back to the email prefix ([displayLabel]).
  final String? displayName;

  WorkspaceMember({
    required this.id,
    required this.workspaceId,
    this.userId,
    required this.email,
    required this.role,
    this.displayName,
  });

  /// What the app shows for this member: the admin-configured display name
  /// when set, otherwise the email prefix.
  String get displayLabel {
    final name = displayName?.trim();
    return (name == null || name.isEmpty) ? email.split('@').first : name;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workspace_id': workspaceId,
      'user_id': userId,
      'email': email,
      'role': role.name,
      'display_name': displayName,
    };
  }

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    return WorkspaceMember(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      userId: json['user_id'] as String?,
      email: json['email'] as String? ?? 'member@example.com',
      role: json['role'].toString().toLowerCase() == 'admin' ? UserRole.admin : UserRole.member,
      displayName: json['display_name'] as String?,
    );
  }
}

/// The display label of the member whose email matches [email]
/// (case-insensitive), or null when no member matches.
String? memberDisplayLabel(List<WorkspaceMember> members, String? email) {
  if (email == null || email.isEmpty) return null;
  for (final member in members) {
    if (member.email.toLowerCase() == email.toLowerCase()) {
      return member.displayLabel;
    }
  }
  return null;
}

class Workspace {
  final String id;
  final String name;
  final String adminId;
  final int autoArchiveDays;
  final bool showArchivedTasks;
  final DateTime createdAt;
  final List<WorkspaceMember> members;

  /// The lanes whose tasks auto-hide after [autoArchiveDays]. New workspaces
  /// are seeded with their Done / Wont Do lanes; an empty list means
  /// auto-expiry is disabled until an admin picks lanes in Settings.
  final List<String> autoExpiryLaneIds;

  Workspace({
    required this.id,
    required this.name,
    required this.adminId,
    this.autoArchiveDays = 14,
    this.showArchivedTasks = false,
    this.autoExpiryLaneIds = const [],
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
      autoExpiryLaneIds:
          List<String>.from(json['auto_expiry_lane_ids'] as List? ?? const []),
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
}
