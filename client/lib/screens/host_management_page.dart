import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../models/ssh_host.dart';
import '../models/ssh_key.dart';
import '../services/host_repository.dart';
import '../services/key_repository.dart';
import 'host_form_page.dart';

class HostManagementPage extends StatefulWidget {
  final bool pickMode;
  final void Function(SSHHost)? onHostOpen;
  final HostRepository hostRepository;
  final KeyRepository keyRepository;
  final bool loggedIn;
  final String? userEmail;

  const HostManagementPage({
    super.key,
    this.pickMode = false,
    this.onHostOpen,
    required this.hostRepository,
    required this.keyRepository,
    required this.loggedIn,
    this.userEmail,
  });

  @override
  State<HostManagementPage> createState() => _HostManagementPageState();
}

class _HostManagementPageState extends State<HostManagementPage> {
  List<SSHHost> _hosts = [];
  List<SSHKey> _keys = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ── Data loading ─────────────────────────────────────────────────────────

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
      setState(() {
        _hosts = _withLocalHost(results[0] as List<SSHHost>);
        if (widget.loggedIn) _keys = results[1] as List<SSHKey>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Host actions ─────────────────────────────────────────────────────────

  Future<void> _openForm({SSHHost? existing}) async {
    final result = await Navigator.push<SSHHost>(
      context,
      MaterialPageRoute(
        builder: (_) => HostFormPage(existing: existing, savedKeys: _keys),
      ),
    );
    if (result == null || !mounted) return;
    await _saveHost(result, existing: existing);
  }

  Future<void> _saveHost(SSHHost host, {SSHHost? existing}) async {
    setState(() => _loading = true);
    try {
      final SSHHost saved;
      if (existing != null) {
        saved = await widget.hostRepository.updateHost(host.copyWith(id: existing.id));
      } else {
        saved = await widget.hostRepository.createHost(host);
      }
      if (!mounted) return;
      setState(() {
        final nonLocal = _hosts.where((h) => !h.isLocal).toList();
        final idx = nonLocal.indexWhere((h) => h.id == (existing?.id ?? saved.id));
        if (idx != -1) {
          nonLocal[idx] = saved;
        } else {
          nonLocal.add(saved);
        }
        _hosts = _withLocalHost(nonLocal);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save host: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteHost(SSHHost host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Host'),
        content: Text('Remove "${host.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _hosts.removeWhere((h) => h.id == host.id));
    try {
      await widget.hostRepository.deleteHost(host.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.redAccent),
      );
      await _loadData(); // re-sync on failure
    }
  }

  void _openHost(SSHHost host) {
    // Resolve saved-key reference to decrypted private key before connecting
    SSHHost resolved = host;
    if ((host.privateKey == null || host.privateKey!.isEmpty) && host.keyId != null) {
      final key = _keys.cast<SSHKey?>().firstWhere(
        (k) => k?.id == host.keyId,
        orElse: () => null,
      );
      if (key?.decryptedPrivateKey != null) {
        resolved = host.copyWith(privateKey: key!.decryptedPrivateKey);
      }
    }

    if (widget.onHostOpen != null) {
      widget.onHostOpen!(resolved);
    } else if (widget.pickMode) {
      Navigator.pop(context, resolved);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<SSHHost> _withLocalHost(List<SSHHost> hosts) {
    if (hosts.any((h) => h.isLocal)) return hosts;
    return [_buildLocalHost(), ...hosts];
  }

  SSHHost _buildLocalHost() {
    final user = Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? 'local';
    return SSHHost(
      id: 'local',
      name: 'Local Terminal',
      hostnameOrIp: Platform.localHostname,
      username: user,
      port: 0,
      isLocal: true,
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SSH Hosts')),
      body: Column(
        children: [
          if (widget.loggedIn) _syncBanner(),
          Expanded(child: _body()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        tooltip: 'Add Host',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _syncBanner() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.cloud_done, color: Colors.lightGreenAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Synced${widget.userEmail != null ? ' · ${widget.userEmail}' : ''}',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            TextButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
      return const Center(child: Text('No hosts yet. Tap + to add one.'));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        itemCount: _hosts.length,
        itemBuilder: (_, i) => _hostTile(_hosts[i]),
      ),
    );
  }

  Widget _hostTile(SSHHost host) {
    final subtitle = host.isLocal
        ? 'Local session · ${host.username}@${host.hostnameOrIp}'
        : '${host.username}@${host.hostnameOrIp}:${host.port}';

    return ListTile(
      leading: Icon(
        host.isLocal ? Icons.computer : Icons.dns,
        color: host.isLocal ? Colors.lightGreenAccent : Colors.tealAccent,
      ),
      title: Text(host.name),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: host.isLocal
          ? null
          : PopupMenuButton<_HostAction>(
              onSelected: (action) {
                if (action == _HostAction.edit) _openForm(existing: host);
                if (action == _HostAction.delete) _deleteHost(host);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: _HostAction.edit, child: Text('Edit')),
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
