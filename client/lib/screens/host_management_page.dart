import 'package:flutter/material.dart';

import '../models/ssh_host.dart';
import '../models/ssh_key.dart';
import '../services/host_repository.dart';
import '../services/key_repository.dart';
import '../theme/app_theme.dart';
import '../utils/platform_utils.dart';
import 'host_form_page.dart';

class HostManagementPage extends StatefulWidget {
  final void Function(SSHHost)? onHostOpen;
  final HostRepository hostRepository;
  final KeyRepository keyRepository;
  final bool loggedIn;
  final String? userEmail;
  final VoidCallback? onLogin; // called when guest taps "Sign In"

  const HostManagementPage({
    super.key,
    this.onHostOpen,
    required this.hostRepository,
    required this.keyRepository,
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
  bool _loading = false;
  String? _error;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.hostRepository.loadHosts(),
        if (widget.loggedIn) widget.keyRepository.loadKeys(),
      ]);
      if (!mounted) return;
      final hosts = results[0] as List<SSHHost>;
      final keys = widget.loggedIn ? results[1] as List<SSHKey> : <SSHKey>[];
      setState(() {
        _hosts = _withLocalHost(hosts);
        _keys = keys;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

    // Resolve saved key reference into the transient privateKey field
    if (host.privateKey == null && host.keyId != null) {
      final key = _keys.cast<SSHKey?>().firstWhere(
        (k) => k?.id == host.keyId,
        orElse: () => null,
      );

      if (key == null) {
        _showError('SSH key not found. Try refreshing the host list.');
        return;
      }

      if (key.decryptedPrivateKey == null) {
        _showError(
          'Could not decrypt the SSH key.\n'
          'Your passphrase may be incorrect. Log out and log back in to re-enter it.',
        );
        return;
      }

      resolved = host.copyWith(privateKey: key.decryptedPrivateKey);
    }

    widget.onHostOpen?.call(resolved);
  }

  Future<void> _openForm({SSHHost? existing}) async {
    if (existing?.isLocal == true) return;

    final isDesktop = AppBreakpoints.of(context) != LayoutClass.compact;
    SSHHost? result;

    if (isDesktop) {
      result = await showDialog<SSHHost>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          backgroundColor: AppColors.surface1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
            child: HostFormPage(
              existing: existing,
              savedKeys: _keys,
              keyRepository: widget.loggedIn ? widget.keyRepository : null,
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
            keyRepository: widget.loggedIn ? widget.keyRepository : null,
          ),
        ),
      );
    }

    if (result == null || !mounted) return;
    _persist(result, existing: existing);
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _hosts.removeWhere((h) => h.id == host.id));
    try {
      await widget.hostRepository.deleteHost(host.id);
    } catch (e) {
      if (mounted) {
        setState(() => _hosts = _withLocalHost([host, ..._hosts.where((h) => !h.isLocal)]));
        _showError('Could not delete: $e');
      }
    }
  }

  Future<void> _persist(SSHHost host, {SSHHost? existing}) async {
    setState(() => _loading = true);
    try {
      final SSHHost saved;
      if (existing != null) {
        saved = await widget.hostRepository.updateHost(host.copyWith(id: existing.id));
      } else {
        saved = await widget.hostRepository.createHost(host);
      }

      final nonLocal = _hosts.where((h) => !h.isLocal).toList();
      final idx = nonLocal.indexWhere((h) => h.id == (existing?.id ?? saved.id));
      if (idx != -1) {
        nonLocal[idx] = saved;
      } else {
        nonLocal.add(saved);
      }

      // Reload keys so any key added inside the form is immediately resolvable
      // (avoids "SSH key not found" on the first connect after adding a host+key).
      final updatedKeys = widget.loggedIn
          ? await widget.keyRepository.loadKeys()
          : <SSHKey>[];

      if (!mounted) return;
      setState(() {
        _hosts = _withLocalHost(nonLocal);
        _keys = updatedKeys;
      });
    } catch (e) {
      _showError('Could not save host: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _banner() {
    if (widget.loggedIn) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        color: AppColors.surface1,
        child: Row(
          children: [
            const Icon(Icons.cloud_done_rounded, color: AppColors.accent, size: 16),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Synced${widget.userEmail != null ? ' · ${widget.userEmail}' : ''}',
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
            ),
            GestureDetector(
              onTap: _loadData,
              child: const Icon(Icons.refresh_rounded, color: AppColors.textTertiary, size: 18),
            ),
          ],
        ),
      );
    }

    // Guest mode banner
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      color: AppColors.surface1,
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.textTertiary, size: 16),
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
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Sign In',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
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
            const Icon(Icons.dns_rounded, size: 56, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.lg),
            Text('No hosts yet', style: AppTypography.title),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Tap + to add your first host',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              onPressed: () => _openForm(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Host', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
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
          onEdit: _hosts[i].isLocal ? null : () => _openForm(existing: _hosts[i]),
          onDelete: _hosts[i].isLocal ? null : () => _deleteHost(_hosts[i]),
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
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (!isLocal && (onEdit != null || onDelete != null))
              PopupMenuButton<_HostAction>(
                icon: const Icon(Icons.more_horiz, color: AppColors.textTertiary),
                onSelected: (action) {
                  if (action == _HostAction.edit) onEdit?.call();
                  if (action == _HostAction.delete) onDelete?.call();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: _HostAction.edit, child: Text('Edit')),
                  const PopupMenuItem(
                    value: _HostAction.delete,
                    child: Text('Delete', style: TextStyle(color: AppColors.danger)),
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
