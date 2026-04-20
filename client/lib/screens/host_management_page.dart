import 'package:flutter/material.dart';

import '../models/ssh_host.dart';
import '../models/ssh_key.dart';
import '../models/workspace.dart';
import '../services/auth_service.dart';
import '../services/host_repository.dart';
import '../services/key_repository.dart';
import '../services/workspace_repository.dart';
import '../theme/app_theme.dart';
import '../utils/platform_utils.dart';
import 'host_form_page.dart';
import 'workspace_detail_page.dart';

class HostManagementPage extends StatefulWidget {
  final void Function(SSHHost)? onHostOpen;
  final HostRepository hostRepository;
  final KeyRepository keyRepository;
  final WorkspaceRepository? workspaceRepository;
  final AuthService? authService;
  final String plan; // 'free' | 'trial' | 'pro'
  final bool loggedIn;
  final String? userEmail;
  final VoidCallback? onLogin;

  const HostManagementPage({
    super.key,
    this.onHostOpen,
    required this.hostRepository,
    required this.keyRepository,
    this.workspaceRepository,
    this.authService,
    this.plan = 'free',
    required this.loggedIn,
    this.userEmail,
    this.onLogin,
  });

  @override
  State<HostManagementPage> createState() => _HostManagementPageState();
}

class _HostManagementPageState extends State<HostManagementPage> {
  List<SSHHost> _hosts = [];
  List<SSHKey> _keys = [];
  List<WorkspaceSession> _workspaces = [];
  String? _selectedWorkspaceId;
  bool _loading = false;
  String? _error;

  // ── Derived state ─────────────────────────────────────────────────────────

  WorkspaceSession? get _selectedWorkspace =>
      _workspaces.where((w) => w.id == _selectedWorkspaceId).firstOrNull;

  bool get _selectedIsDefault => _selectedWorkspace?.isDefault ?? true;

  /// Can add/edit/delete hosts in the current workspace.
  bool get _canManage =>
      !widget.loggedIn || (_selectedWorkspace?.role.canManageHosts ?? true);

  bool get _canCreateWorkspace => widget.plan != 'free';

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.loggedIn && widget.workspaceRepository != null) {
      try {
        final workspaces = await widget.workspaceRepository!.loadWorkspaces();
        final defaultWs = workspaces.where((w) => w.isDefault).firstOrNull;
        // Keep SharedPreferences in sync so KeyRepository.currentSession()
        // always returns valid workspace data even after a migration.
        if (widget.authService != null) {
          await widget.authService!.saveWorkspacesCache(workspaces);
        }
        if (mounted) {
          setState(() {
            _workspaces = workspaces;
            _selectedWorkspaceId = defaultWs?.id;
          });
        }
      } catch (_) {}
    }
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wsId = _selectedWorkspaceId;
      final List<SSHHost> hosts;
      final List<SSHKey> keys;

      if (wsId != null && widget.workspaceRepository != null) {
        final results = await Future.wait([
          widget.workspaceRepository!.loadWorkspaceHosts(wsId),
          widget.workspaceRepository!.loadWorkspaceKeys(wsId),
        ]);
        hosts = results[0] as List<SSHHost>;
        keys = results[1] as List<SSHKey>;
      } else {
        final results = await Future.wait([
          widget.hostRepository.loadHosts(),
          if (widget.loggedIn) widget.keyRepository.loadKeys(),
        ]);
        hosts = results[0] as List<SSHHost>;
        keys = widget.loggedIn && results.length > 1
            ? results[1] as List<SSHKey>
            : <SSHKey>[];
      }

      if (!mounted) return;
      setState(() {
        _hosts = _selectedIsDefault ? _withLocalHost(hosts) : hosts;
        _keys = keys;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectWorkspace(WorkspaceSession ws) async {
    setState(() => _selectedWorkspaceId = ws.id);
    await _loadData();
  }

  // ── Workspace picker ──────────────────────────────────────────────────────

  void _showWorkspacePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: Text('Switch Workspace', style: AppTypography.title),
            ),
            ..._workspaces.map((ws) {
              final isSelected = ws.id == _selectedWorkspaceId;
              return ListTile(
                dense: true,
                leading: Icon(
                  ws.isDefault
                      ? Icons.person_rounded
                      : Icons.group_rounded,
                  size: 18,
                  color: isSelected
                      ? AppColors.accent
                      : AppColors.textTertiary,
                ),
                title: Text(
                  ws.isDefault ? 'Personal' : ws.name,
                  style: TextStyle(
                    fontSize: 14,
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.textPrimary,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_rounded,
                        size: 16, color: AppColors.accent)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (!isSelected) _selectWorkspace(ws);
                },
              );
            }),
            const Divider(height: 1, color: AppColors.border),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.add_circle_outline_rounded,
                size: 18,
                color: _canCreateWorkspace
                    ? AppColors.accent
                    : AppColors.textDisabled,
              ),
              title: Text(
                'New Workspace',
                style: TextStyle(
                  fontSize: 14,
                  color: _canCreateWorkspace
                      ? AppColors.textPrimary
                      : AppColors.textDisabled,
                ),
              ),
              trailing: !_canCreateWorkspace
                  ? const Icon(Icons.lock_outline_rounded,
                      size: 14, color: AppColors.textDisabled)
                  : null,
              onTap: _canCreateWorkspace
                  ? () {
                      Navigator.pop(ctx);
                      _createWorkspace();
                    }
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _createWorkspace() async {
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        title: const Text('New Workspace'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Workspace name',
            hintText: 'e.g. Backend Team',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create',
                  style: TextStyle(color: AppColors.accent))),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (confirmed != true || name.isEmpty || !mounted) return;

    setState(() => _loading = true);
    try {
      final ws = await widget.workspaceRepository!.createWorkspace(name);
      if (!mounted) return;
      setState(() {
        _workspaces.add(ws);
        _selectedWorkspaceId = ws.id;
        _hosts = [];
        _keys = [];
      });
    } catch (e) {
      if (mounted) _showSnack('Could not create workspace: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Member management ─────────────────────────────────────────────────────

  void _openMembers() {
    final ws = _selectedWorkspace;
    if (ws == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkspaceDetailPage(
        workspaceSession: ws,
        workspaceRepository: widget.workspaceRepository!,
        authService: widget.authService,
        onWorkspaceDeleted: () {
          Navigator.of(context).pop();
          setState(() {
            _workspaces.removeWhere((w) => w.id == ws.id);
            final defaultWs =
                _workspaces.where((w) => w.isDefault).firstOrNull;
            _selectedWorkspaceId = defaultWs?.id;
          });
          _loadData();
        },
      ),
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<SSHHost> _withLocalHost(List<SSHHost> hosts) {
    if (!PlatformUtils.supportsLocalShell) return hosts;
    if (hosts.any((h) => h.isLocal)) return hosts;
    final user = PlatformUtils.localUsername ?? 'local';
    return [
      SSHHost(
        id: 'local',
        name: 'Local Terminal',
        hostnameOrIp: PlatformUtils.localHostname,
        username: user,
        port: 0,
        isLocal: true,
      ),
      ...hosts,
    ];
  }

  void _openHost(SSHHost host) {
    SSHHost resolved = host;
    if (host.privateKey == null && host.keyId != null) {
      final key = _keys.cast<SSHKey?>().firstWhere(
        (k) => k?.id == host.keyId,
        orElse: () => null,
      );
      if (key == null) {
        _showSnack('SSH key not found. Try refreshing the host list.');
        return;
      }
      if (key.decryptedPrivateKey == null) {
        _showSnack(
          'Could not decrypt the SSH key. Log out and back in to re-enter your passphrase.',
        );
        return;
      }
      resolved = host.copyWith(privateKey: key.decryptedPrivateKey);
    }
    widget.onHostOpen?.call(resolved);
  }

  Future<void> _openForm({SSHHost? existing}) async {
    if (existing?.isLocal == true) return;

    // Key repo scoped to the currently selected workspace
    KeyRepository? scopedKeyRepo;
    if (widget.loggedIn &&
        widget.authService != null &&
        widget.workspaceRepository != null &&
        _selectedWorkspaceId != null) {
      scopedKeyRepo = KeyRepository(
        authService: widget.authService!,
        workspaceRepository: widget.workspaceRepository!,
        fixedWorkspaceId: _selectedWorkspaceId,
      );
    } else if (widget.loggedIn) {
      scopedKeyRepo = widget.keyRepository;
    }

    final isDesktop = AppBreakpoints.of(context) != LayoutClass.compact;
    SSHHost? result;

    if (isDesktop) {
      result = await showDialog<SSHHost>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          backgroundColor: AppColors.surface1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
            child: HostFormPage(
              existing: existing,
              savedKeys: _keys,
              keyRepository: scopedKeyRepo,
              asDialog: true,
            ),
          ),
        ),
      );
    } else {
      result = await Navigator.of(context).push<SSHHost>(
        MaterialPageRoute(
          builder: (_) => HostFormPage(
            existing: existing,
            savedKeys: _keys,
            keyRepository: scopedKeyRepo,
          ),
        ),
      );
    }

    if (result == null || !mounted) return;
    await _persist(result, existing: existing);
  }

  Future<void> _deleteHost(SSHHost host) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Host'),
        content: Text('Remove "${host.name}"?'),
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

    setState(() => _hosts.removeWhere((h) => h.id == host.id));
    try {
      final wsId = _selectedWorkspaceId;
      if (wsId != null && widget.workspaceRepository != null) {
        await widget.workspaceRepository!.deleteWorkspaceHost(wsId, host.id);
      } else {
        await widget.hostRepository.deleteHost(host.id);
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _hosts = _selectedIsDefault
                ? _withLocalHost([host, ..._hosts.where((h) => !h.isLocal)])
                : [host, ..._hosts]);
        _showSnack('Could not delete: $e');
      }
    }
  }

  Future<void> _persist(SSHHost host, {SSHHost? existing}) async {
    setState(() => _loading = true);
    try {
      final SSHHost saved;
      final wsId = _selectedWorkspaceId;

      if (wsId != null && widget.workspaceRepository != null) {
        if (existing != null) {
          saved = await widget.workspaceRepository!
              .updateWorkspaceHost(wsId, host.copyWith(id: existing.id));
        } else {
          saved =
              await widget.workspaceRepository!.createWorkspaceHost(wsId, host);
        }
      } else {
        if (existing != null) {
          saved = await widget.hostRepository
              .updateHost(host.copyWith(id: existing.id));
        } else {
          saved = await widget.hostRepository.createHost(host);
        }
      }

      final nonLocal = _hosts.where((h) => !h.isLocal).toList();
      final idx =
          nonLocal.indexWhere((h) => h.id == (existing?.id ?? saved.id));
      if (idx != -1) {
        nonLocal[idx] = saved;
      } else {
        nonLocal.add(saved);
      }

      // Reload keys in case a new key was added inside the form
      final updatedKeys = wsId != null && widget.workspaceRepository != null
          ? await widget.workspaceRepository!.loadWorkspaceKeys(wsId)
          : widget.loggedIn
              ? await widget.keyRepository.loadKeys()
              : <SSHKey>[];

      if (!mounted) return;
      setState(() {
        _hosts = _selectedIsDefault ? _withLocalHost(nonLocal) : nonLocal;
        _keys = updatedKeys;
      });
    } catch (e) {
      _showSnack('Could not save host: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.surface2),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _banner(),
          Expanded(child: _body()),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton(
              onPressed: () => _openForm(),
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _banner() {
    if (!widget.loggedIn) return _guestBanner();

    final ws = _selectedWorkspace;
    final wsName = ws == null
        ? 'Personal'
        : ws.isDefault
            ? 'Personal'
            : ws.name;
    final isTeam = ws != null && !ws.isDefault;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface1,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Workspace selector chip
          GestureDetector(
            onTap: _showWorkspacePicker,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isTeam ? Icons.group_rounded : Icons.person_rounded,
                  size: 14,
                  color: AppColors.accent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  wsName,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 14, color: AppColors.textTertiary),
              ],
            ),
          ),

          // Divider
          Container(
            width: 1,
            height: 12,
            color: AppColors.border,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),

          // Sync status
          const Icon(Icons.cloud_done_rounded,
              color: AppColors.accent, size: 14),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              widget.userEmail != null
                  ? 'Synced · ${widget.userEmail}'
                  : 'Synced',
              style: const TextStyle(
                  color: AppColors.textTertiary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Members button (team workspaces only)
          if (isTeam) ...[
            GestureDetector(
              onTap: _openMembers,
              child: const Tooltip(
                message: 'Members',
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: Icon(Icons.people_outline_rounded,
                      size: 16, color: AppColors.textTertiary),
                ),
              ),
            ),
          ],

          // Refresh
          GestureDetector(
            onTap: _loadData,
            child: const Padding(
              padding: EdgeInsets.only(left: AppSpacing.xs),
              child: Icon(Icons.refresh_rounded,
                  color: AppColors.textTertiary, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guestBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface1,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.textTertiary, size: 16),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text(
              'Hosts are local only · Sign in to sync',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          ),
          if (widget.onLogin != null)
            TextButton(
              onPressed: widget.onLogin,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Sign In',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: AppSpacing.md),
            TextButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }

    final userHosts = _hosts.where((h) => !h.isLocal).toList();
    if (userHosts.isEmpty && !_hosts.any((h) => h.isLocal)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_rounded,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.lg),
            Text('No hosts yet', style: AppTypography.title),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _canManage
                  ? 'Tap + to add your first host'
                  : 'No shared hosts in this workspace yet',
              style:
                  const TextStyle(color: AppColors.textTertiary, fontSize: 14),
            ),
            if (_canManage) ...[
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton.icon(
                onPressed: () => _openForm(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Host',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.accent,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: _hosts.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.borderSubtle),
        itemBuilder: (_, i) => _HostCard(
          host: _hosts[i],
          onTap: () => _openHost(_hosts[i]),
          onEdit: (_hosts[i].isLocal || !_canManage)
              ? null
              : () => _openForm(existing: _hosts[i]),
          onDelete: (_hosts[i].isLocal || !_canManage)
              ? null
              : () => _deleteHost(_hosts[i]),
        ),
      ),
    );
  }
}

enum _HostAction { edit, delete }

// ── Host card ─────────────────────────────────────────────────────────────────

class _HostCard extends StatelessWidget {
  final SSHHost host;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _HostCard({
    required this.host,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isLocal = host.isLocal;
    final subtitle = isLocal
        ? '${host.username}@${host.hostnameOrIp}'
        : '${host.username}@${host.hostnameOrIp}:${host.port}';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            _HostAvatar(name: host.name, isLocal: isLocal),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        color: AppColors.textTertiary, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (!isLocal && (onEdit != null || onDelete != null))
              PopupMenuButton<_HostAction>(
                icon: const Icon(Icons.more_horiz,
                    color: AppColors.textTertiary),
                onSelected: (action) {
                  if (action == _HostAction.edit) onEdit?.call();
                  if (action == _HostAction.delete) onDelete?.call();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: _HostAction.edit, child: Text('Edit')),
                  const PopupMenuItem(
                    value: _HostAction.delete,
                    child: Text('Delete',
                        style: TextStyle(color: AppColors.danger)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _HostAvatar extends StatelessWidget {
  final String name;
  final bool isLocal;

  const _HostAvatar({required this.name, required this.isLocal});

  Color get _color {
    if (isLocal) return AppColors.accent;
    const colors = [
      Color(0xFF4C8BF5),
      Color(0xFFE27C54),
      Color(0xFF9B59B6),
      Color(0xFF1ABC9C),
      Color(0xFFE74C3C),
      Color(0xFF3498DB),
    ];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.30)),
      ),
      child: isLocal
          ? Icon(Icons.computer_rounded, color: _color, size: 20)
          : Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: _color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
    );
  }
}
