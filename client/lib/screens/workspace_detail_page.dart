import 'package:flutter/material.dart';

import '../models/workspace.dart';
import '../services/auth_service.dart';
import '../services/workspace_repository.dart';
import '../theme/app_theme.dart';

/// Members management page for a team workspace.
/// Hosts are managed directly in the main host list (via workspace selector).
class WorkspaceDetailPage extends StatefulWidget {
  final WorkspaceSession workspaceSession;
  final WorkspaceRepository workspaceRepository;
  final AuthService? authService;
  final VoidCallback? onWorkspaceDeleted;

  const WorkspaceDetailPage({
    super.key,
    required this.workspaceSession,
    required this.workspaceRepository,
    this.authService,
    this.onWorkspaceDeleted,
  });

  @override
  State<WorkspaceDetailPage> createState() => _WorkspaceDetailPageState();
}

class _WorkspaceDetailPageState extends State<WorkspaceDetailPage> {
  WorkspaceDetail? _detail;
  bool _loading = false;
  String? _error;

  bool get _canManage => widget.workspaceSession.role.canManageMembers;
  bool get _isOwner => widget.workspaceSession.role.isOwner;
  String get _workspaceId => widget.workspaceSession.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail =
          await widget.workspaceRepository.loadWorkspaceDetail(_workspaceId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _inviteMember() async {
    final emailCtrl = TextEditingController();
    WorkspaceRole selectedRole = WorkspaceRole.member;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.surface1,
          title: const Text('Invite Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration:
                    const InputDecoration(labelText: 'Email address'),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<WorkspaceRole>(
                initialValue: selectedRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [WorkspaceRole.admin, WorkspaceRole.member]
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(_roleName(r)),
                        ))
                    .toList(),
                onChanged: (r) => setS(() => selectedRole = r!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Invite',
                    style: TextStyle(color: AppColors.accent))),
          ],
        ),
      ),
    );

    final email = emailCtrl.text.trim();
    emailCtrl.dispose();
    if (confirmed != true || email.isEmpty || !mounted) return;

    setState(() => _loading = true);
    try {
      final encKey =
          widget.workspaceSession.encryptedWorkspaceKey ?? '';
      final member = await widget.workspaceRepository.inviteMember(
          _workspaceId, email, selectedRole, encKey);
      if (mounted && _detail != null) {
        setState(() {
          _detail = WorkspaceDetail(
            workspace: _detail!.workspace,
            members: [..._detail!.members, member],
            encryptedWorkspaceKey: _detail!.encryptedWorkspaceKey,
          );
        });
      }
    } catch (e) {
      if (mounted) _showSnack('Could not invite: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeMember(WorkspaceMember member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.email} from this workspace?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirm != true || _detail == null) return;

    setState(() => _loading = true);
    try {
      await widget.workspaceRepository
          .removeMember(_workspaceId, member.userId, _detail!);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnack('Could not remove member: $e');
      }
    }
  }

  Future<void> _deleteWorkspace() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Workspace'),
        content: Text(
            'Permanently delete "${widget.workspaceSession.name}"? '
            'All shared hosts and keys will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      await widget.workspaceRepository.deleteWorkspace(_workspaceId);
      widget.onWorkspaceDeleted?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnack('Could not delete workspace: $e');
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.surface2),
    );
  }

  String _roleName(WorkspaceRole r) =>
      r.value[0].toUpperCase() + r.value.substring(1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface1,
        elevation: 0,
        title: Text(widget.workspaceSession.name, style: AppTypography.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
        actions: [
          if (_canManage)
            IconButton(
              icon: const Icon(Icons.person_add_rounded,
                  size: 20, color: AppColors.accent),
              tooltip: 'Invite member',
              onPressed: _inviteMember,
            ),
          if (_isOwner)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _deleteWorkspace();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete Workspace',
                      style: TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
        ],
      ),
      body: _loading && _detail == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style:
                              const TextStyle(color: AppColors.danger)),
                      const SizedBox(height: AppSpacing.md),
                      TextButton(
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.accent,
                  child: _detail == null || _detail!.members.isEmpty
                      ? const Center(
                          child: Text('No members yet',
                              style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 14)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm),
                          itemCount: _detail!.members.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: AppColors.borderSubtle),
                          itemBuilder: (_, i) {
                            final m = _detail!.members[i];
                            return _MemberTile(
                              member: m,
                              roleName: _roleName(m.role),
                              onRemove:
                                  _canManage && !m.role.isOwner
                                      ? () => _removeMember(m)
                                      : null,
                            );
                          },
                        ),
                ),
    );
  }
}

// ── Member tile ───────────────────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  final WorkspaceMember member;
  final String roleName;
  final VoidCallback? onRemove;

  const _MemberTile({
    required this.member,
    required this.roleName,
    this.onRemove,
  });

  Color _roleColor(WorkspaceRole r) {
    switch (r) {
      case WorkspaceRole.owner:
        return AppColors.accent;
      case WorkspaceRole.admin:
        return AppColors.warning;
      case WorkspaceRole.member:
        return AppColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPending = member.inviteStatus == 'pending';
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.person_rounded,
                size: 16, color: AppColors.textTertiary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.email,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _Badge(
                        label: roleName,
                        color: _roleColor(member.role)),
                    if (isPending) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const _Badge(
                          label: 'Pending',
                          color: AppColors.textTertiary),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.person_remove_outlined,
                  size: 18, color: AppColors.danger),
              onPressed: onRemove,
              tooltip: 'Remove',
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500)),
    );
  }
}
