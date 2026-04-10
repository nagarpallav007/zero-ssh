import 'dart:io' show Platform, File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../models/ssh_host.dart';
import '../models/ssh_key.dart';
import '../services/host_repository.dart';
import '../services/key_repository.dart';

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

  SSHHost _buildLocalHost() {
    final currentUser =
        Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? 'local';
    return SSHHost(
      id: 'local',
      name: 'Local Terminal',
      hostnameOrIp: Platform.localHostname,
      username: currentUser,
      port: 0,
      isLocal: true,
    );
  }

  List<SSHHost> _attachLocalHost(List<SSHHost> hosts) {
    final hasLocal = hosts.any((h) => h.isLocal);
    if (hasLocal) return hosts;
    return [_buildLocalHost(), ...hosts];
  }

  @override
  void initState() {
    super.initState();
    _loadHosts();
    if (widget.loggedIn) {
      _loadKeys();
    }
  }

  Future<void> _loadKeys() async {
    try {
      final keys = await widget.keyRepository.loadKeys();
      if (mounted) setState(() => _keys = keys);
    } catch (e) {
      // swallow errors for now; UI remains functional
      debugPrint('Error loading keys: $e');
    }
  }

  Future<void> _loadHosts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = await widget.hostRepository.loadHosts();
      final withLocal = _attachLocalHost(loaded);

      // IMPORTANT: Check if widget is still mounted before calling setState
      if (mounted) {
        setState(() => _hosts = withLocal);
      }
    } catch (e) {
      // Handle any errors that might occur during loading
      if (mounted) {
        // You could show an error message or handle the error state here
        setState(() => _error = 'Error loading hosts: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addOrEditHost({SSHHost? existing}) {
    if (existing?.isLocal == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local terminal is built-in and cannot be edited.')),
      );
      return;
    }

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final hostCtrl = TextEditingController(text: existing?.hostnameOrIp ?? '');
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final portCtrl = TextEditingController(text: existing?.port.toString() ?? '22');
    final passwordCtrl = TextEditingController(text: existing?.password ?? '');
    final keyFileCtrl = TextEditingController(text: existing?.keyFilePath ?? '');
    final privateKeyCtrl = TextEditingController(text: existing?.privateKey ?? '');
    String? selectedKeyId = existing?.keyId;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(existing == null ? 'Add Host' : 'Edit Host'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: hostCtrl,
                  decoration: const InputDecoration(labelText: 'Hostname / IP address'),
                ),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                TextField(
                  controller: portCtrl,
                  decoration: const InputDecoration(labelText: 'Port'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                TextField(
                  controller: passwordCtrl,
                  decoration: const InputDecoration(labelText: 'Password (optional)'),
                  obscureText: true,
                ),
                if (widget.loggedIn && _keys.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    value: selectedKeyId,
                    decoration: const InputDecoration(labelText: 'Use saved key (optional)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      ..._keys.map(
                        (k) => DropdownMenuItem(
                          value: k.id,
                          child: Text(k.label ?? 'Key ${k.id.substring(0, 6)}'),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setStateDialog(() {
                        selectedKeyId = val;
                      });
                    },
                  ),
                TextField(
                  controller: privateKeyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Private Key (PEM, optional — creates/updates saved key)',
                  ),
                  maxLines: 3,
                ),
                Row(
                  children: [
                    // Key File Path TextField (readonly, filled from picker)
                    Expanded(
                      child: TextField(
                        controller: keyFileCtrl,
                        decoration: const InputDecoration(labelText: 'Key File Path (optional)'),
                        readOnly: true,
                      ),
                    ),
                    IconButton(
                        tooltip: 'Pick Key File',
                        icon: const Icon(Icons.folder_open),
                        onPressed: () async {
                          try {
                            final result = await FilePicker.platform.pickFiles(type: FileType.any);
                            if (result != null && result.files.single.path != null) {
                              setStateDialog(() {
                                keyFileCtrl.text = result.files.single.path!;
                              });
                            }
                          } catch (e) {
                            // Handle file picker errors
                            print('File picker error: $e');
                          }
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (hostCtrl.text.trim().isEmpty ||
                    userCtrl.text.trim().isEmpty ||
                    nameCtrl.text.trim().isEmpty) {
                  // Simple validation: name, host, and username required
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Name, Hostname/IP, and Username are required.")),
                  );
                  return;
                }

                final newHost = SSHHost(
                  id: existing?.id ?? '',
                  name: nameCtrl.text.trim(),
                  hostnameOrIp: hostCtrl.text.trim(),
                  username: userCtrl.text.trim(),
                  port: int.tryParse(portCtrl.text.trim()) ?? 22,
                  keyId: selectedKeyId,
                  password: passwordCtrl.text.isNotEmpty ? passwordCtrl.text : null,
                  keyFilePath: keyFileCtrl.text.isNotEmpty ? keyFileCtrl.text : null,
                  privateKey: privateKeyCtrl.text.isNotEmpty ? privateKeyCtrl.text : null,
                );

                // Check mounted before setState
                if (mounted) {
                  _persistHost(newHost, existing: existing);
                }
                
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteHost(String id) {
    if (!mounted) return;
    setState(() => _hosts.removeWhere((h) => h.id == id && !h.isLocal));
    widget.hostRepository.deleteHost(id).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting host: $e')),
      );
    });
  }

  void _openTerminalTabs(SSHHost host) {
    SSHHost resolvedHost = host;
    // If the host uses a saved key reference, resolve the decrypted private key
    if ((host.privateKey == null || host.privateKey!.isEmpty) && host.keyId != null) {
      final key = _keys.cast<SSHKey?>().firstWhere(
        (k) => k?.id == host.keyId,
        orElse: () => null,
      );
      if (key?.decryptedPrivateKey != null) {
        resolvedHost = host.copyWith(privateKey: key!.decryptedPrivateKey);
      }
    }
    if (widget.onHostOpen != null) {
      widget.onHostOpen!(resolvedHost);
    } else if (widget.pickMode) {
      Navigator.pop(context, resolvedHost);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SSH Hosts')),
      body: Column(
        children: [
          if (widget.loggedIn)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  const Icon(Icons.cloud_done, color: Colors.lightGreenAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Synced${widget.userEmail != null ? ' • ${widget.userEmail}' : ''}'),
                  ),
                  TextButton.icon(
                    onPressed: _loadHosts,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _hosts.isEmpty
                    ? Center(child: Text(_error ?? 'No hosts yet. Add one!'))
                    : RefreshIndicator(
                        onRefresh: _loadHosts,
                        child: ListView.builder(
                          itemCount: _hosts.length,
                          itemBuilder: (context, index) {
                            final host = _hosts[index];
                            final isLocal = host.isLocal;
                            final subtitle = isLocal
                                ? 'Local session (${host.username}@${host.hostnameOrIp})'
                                : '${host.username}@${host.hostnameOrIp}:${host.port}';
                            return ListTile(
                              title: Text(host.name),
                              subtitle: Text(subtitle),
                              trailing: isLocal
                                  ? const Icon(Icons.computer, color: Colors.lightGreenAccent)
                                  : PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          _addOrEditHost(existing: host);
                                        } else if (value == 'delete') {
                                          _deleteHost(host.id);
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                      ],
                                    ),
                              onTap: () => _openTerminalTabs(host),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditHost(),
        child: const Icon(Icons.add),
      ),
    );
  }

  @override
  void dispose() {
    // Clean up any resources if needed
    super.dispose();
  }

  Future<void> _persistHost(SSHHost newHost, {SSHHost? existing}) async {
    setState(() => _loading = true);
    try {
      final hostToSave = await _attachFileKeyIfNeeded(newHost);
      SSHHost saved;
      if (existing != null) {
        saved = await widget.hostRepository.updateHost(hostToSave.copyWith(id: existing.id));
      } else {
        saved = await widget.hostRepository.createHost(hostToSave);
      }

      final nonLocal = _hosts.where((h) => !h.isLocal).toList();
      final idx = nonLocal.indexWhere((h) => h.id == (existing?.id ?? saved.id));
      if (idx != -1) {
        nonLocal[idx] = saved;
      } else {
        nonLocal.add(saved);
      }

      setState(() {
        _hosts = _attachLocalHost(nonLocal);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving host: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<SSHHost> _attachFileKeyIfNeeded(SSHHost host) async {
    if ((host.privateKey ?? '').isNotEmpty) return host;
    if ((host.keyFilePath ?? '').isEmpty) return host;

    final file = File(host.keyFilePath!);
    if (!await file.exists()) {
      throw Exception('Private key file not found: ${host.keyFilePath}');
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      throw Exception('Private key file is empty');
    }
    return host.copyWith(privateKey: content);
  }
}
