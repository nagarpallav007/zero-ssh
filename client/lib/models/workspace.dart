enum WorkspaceRole { owner, admin, member }

extension WorkspaceRoleExt on WorkspaceRole {
  String get value => name; // 'owner' | 'admin' | 'member'

  bool get canManageHosts => this == WorkspaceRole.owner || this == WorkspaceRole.admin;
  bool get canManageMembers => this == WorkspaceRole.owner || this == WorkspaceRole.admin;
  bool get isOwner => this == WorkspaceRole.owner;
}

WorkspaceRole workspaceRoleFromString(String s) {
  switch (s) {
    case 'owner':
      return WorkspaceRole.owner;
    case 'admin':
      return WorkspaceRole.admin;
    default:
      return WorkspaceRole.member;
  }
}

class WorkspaceMember {
  final String id;
  final String userId;
  final String email;
  final String? publicKey;
  final WorkspaceRole role;
  final String inviteStatus; // 'pending' | 'accepted'
  final String? encryptedWorkspaceKey;
  final DateTime? joinedAt;

  const WorkspaceMember({
    required this.id,
    required this.userId,
    required this.email,
    this.publicKey,
    required this.role,
    required this.inviteStatus,
    this.encryptedWorkspaceKey,
    this.joinedAt,
  });

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) => WorkspaceMember(
        id: json['id'] as String,
        userId: json['userId'] as String,
        email: json['email'] as String,
        publicKey: json['publicKey'] as String?,
        role: workspaceRoleFromString(json['role'] as String),
        inviteStatus: json['inviteStatus'] as String? ?? 'accepted',
        encryptedWorkspaceKey: json['encryptedWorkspaceKey'] as String?,
        joinedAt: json['joinedAt'] != null ? DateTime.parse(json['joinedAt'] as String) : null,
      );
}

class Workspace {
  final String id;
  final String name;
  final bool isDefault;
  final String ownerId;
  final DateTime createdAt;

  const Workspace({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.ownerId,
    required this.createdAt,
  });

  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
        id: json['id'] as String,
        name: json['name'] as String,
        isDefault: json['isDefault'] as bool? ?? false,
        ownerId: json['ownerId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class WorkspaceDetail {
  final Workspace workspace;
  final List<WorkspaceMember> members;
  final String? encryptedWorkspaceKey;

  const WorkspaceDetail({
    required this.workspace,
    required this.members,
    required this.encryptedWorkspaceKey,
  });
}

/// Lightweight workspace info embedded in the auth session (from login response).
class WorkspaceSession {
  final String id;
  final String name;
  final bool isDefault;
  final WorkspaceRole role;
  final String? encryptedWorkspaceKey;
  final String inviteStatus;

  const WorkspaceSession({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.role,
    required this.encryptedWorkspaceKey,
    required this.inviteStatus,
  });

  factory WorkspaceSession.fromJson(Map<String, dynamic> json) => WorkspaceSession(
        id: json['id'] as String,
        name: json['name'] as String,
        isDefault: json['isDefault'] as bool? ?? false,
        role: workspaceRoleFromString(json['role'] as String),
        encryptedWorkspaceKey: json['encryptedWorkspaceKey'] as String?,
        inviteStatus: json['inviteStatus'] as String? ?? 'accepted',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isDefault': isDefault,
        'role': role.value,
        'encryptedWorkspaceKey': encryptedWorkspaceKey,
        'inviteStatus': inviteStatus,
      };
}
