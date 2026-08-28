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
  final DateTime createdAt;
  final List<WorkspaceMember> members;

  Workspace({
    required this.id,
    required this.name,
    required this.adminId,
    this.autoArchiveDays = 14,
    DateTime? createdAt,
    this.members = const [],
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'admin_id': adminId,
      'auto_archive_days': autoArchiveDays,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Workspace.fromJson(Map<String, dynamic> json, {List<WorkspaceMember>? members}) {
    return Workspace(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Default Workspace',
      adminId: json['admin_id'] as String? ?? '',
      autoArchiveDays: json['auto_archive_days'] as int? ?? 14,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      members: members ?? [],
    );
  }

  Workspace copyWith({
    String? name,
    int? autoArchiveDays,
    List<WorkspaceMember>? members,
  }) {
    return Workspace(
      id: id,
      name: name ?? this.name,
      adminId: adminId,
      autoArchiveDays: autoArchiveDays ?? this.autoArchiveDays,
      createdAt: createdAt,
      members: members ?? this.members,
    );
  }
}
