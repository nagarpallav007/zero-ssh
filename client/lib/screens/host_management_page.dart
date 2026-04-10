import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../models/ssh_host.dart';
import '../models/ssh_key.dart';
import '../services/host_repository.dart';
import '../services/key_repository.dart';
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
    if (hosts.any((h) => h.isLocal)) return hosts;
    final user = Platform.environment['USER'] ??
        Platform.environment['USERNAME'] ??
        'local';
    return [
      SSHHost(
        id: 'local',
        name: 'Local Terminal',
        hostnameOrIp: Platform.localHostname,
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
        // Key exists but decryption failed — passphrase was likely wrong
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

    final result = await Navigator.of(context).push<SSHHost>(
      MaterialPageRoute(
        builder: (_) => HostFormPage(
          existing: existing,
          savedKeys: _keys,
          keyRepository: widget.loggedIn ? widget.keyRepository : null,
        ),
      ),
    );
    if (result == null || !mounted) return;
    _persist(result, existing: existing);
  }

  Future<void> _deleteHost(SSHHost host) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1E2A),
        title: const Text('Delete Host'),
        content: Text('Remove "${host.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
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
      setState(() => _hosts = _withLocalHost(nonLocal));
    } catch (e) {
      _showError('Could not save host: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      body: Column(
        children: [
          _banner(),
          Expanded(child: _body()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        backgroundColor: const Color(0xFF20C997),
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _banner() {
    if (widget.loggedIn) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFF151720),
        child: Row(
          children: [
            const Icon(Icons.cloud_done_rounded, color: Color(0xFF20C997), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Synced${widget.userEmail != null ? ' · ${widget.userEmail}' : ''}',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ),
            GestureDetector(
              onTap: _loadData,
              child: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 18),
            ),
          ],
        ),
      );
    }

    // Guest mode banner
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF1A1C28),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Hosts are local only · Sign in to sync',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          if (widget.onLogin != null)
            TextButton(
              onPressed: widget.onLogin,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF20C997),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            TextButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_hosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_rounded, size: 48, color: Colors.white12),
            const SizedBox(height: 12),
            const Text('No hosts yet', style: TextStyle(color: Colors.white38)),
            const SizedBox(height: 4),
            const Text(
              'Tap + to add your first host',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF20C997),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _hosts.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 72, color: Color(0x14FFFFFF)),
        itemBuilder: (_, i) => _hostTile(_hosts[i]),
      ),
    );
  }

  Widget _hostTile(SSHHost host) {
    final isLocal = host.isLocal;
    final subtitle = isLocal
        ? '${host.username}@${host.hostnameOrIp}'
        : '${host.username}@${host.hostnameOrIp}:${host.port}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _HostAvatar(name: host.name, isLocal: isLocal),
      title: Text(
        host.name,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white38, fontSize: 13),
      ),
      trailing: isLocal
          ? null
          : PopupMenuButton<_HostAction>(
              icon: const Icon(Icons.more_horiz, color: Colors.white38),
              color: const Color(0xFF1C1E2A),
              onSelected: (action) {
                if (action == _HostAction.edit) _openForm(existing: host);
                if (action == _HostAction.delete) _deleteHost(host);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _HostAction.edit,
                  child: Text('Edit'),
                ),
                PopupMenuItem(
                  value: _HostAction.delete,
                  child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
      onTap: () => _openHost(host),
    );
  }
}

enum _HostAction { edit, delete }

class _HostAvatar extends StatelessWidget {
  final String name;
  final bool isLocal;

  const _HostAvatar({required this.name, required this.isLocal});

  Color get _color {
    if (isLocal) return const Color(0xFF20C997);
    final colors = [
      const Color(0xFF4C8BF5),
      const Color(0xFFE27C54),
      const Color(0xFF9B59B6),
      const Color(0xFF1ABC9C),
      const Color(0xFFE74C3C),
      const Color(0xFF3498DB),
    ];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withOpacity(0.35)),
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
