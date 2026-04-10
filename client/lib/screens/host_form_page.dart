import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ssh_host.dart';
import '../models/ssh_key.dart';

/// Full-screen add / edit form for an SSH host.
///
/// Push via [Navigator] and await the result:
/// ```dart
/// final host = await Navigator.push<SSHHost>(
///   context,
///   MaterialPageRoute(builder: (_) => HostFormPage(savedKeys: _keys)),
/// );
/// if (host != null) _save(host);
/// ```
class HostFormPage extends StatefulWidget {
  final SSHHost? existing;
  final List<SSHKey> savedKeys;

  const HostFormPage({super.key, this.existing, required this.savedKeys});

  @override
  State<HostFormPage> createState() => _HostFormPageState();
}

class _HostFormPageState extends State<HostFormPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _keyFileCtrl;
  late final TextEditingController _privateKeyCtrl;

  String? _selectedKeyId;
  bool _obscurePassword = true;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    _nameCtrl = TextEditingController(text: h?.name ?? '');
    _hostCtrl = TextEditingController(text: h?.hostnameOrIp ?? '');
    _userCtrl = TextEditingController(text: h?.username ?? '');
    _portCtrl = TextEditingController(text: h?.port.toString() ?? '22');
    _passwordCtrl = TextEditingController(text: h?.password ?? '');
    _keyFileCtrl = TextEditingController(text: h?.keyFilePath ?? '');
    _privateKeyCtrl = TextEditingController(text: h?.privateKey ?? '');
    _selectedKeyId = h?.keyId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _userCtrl.dispose();
    _portCtrl.dispose();
    _passwordCtrl.dispose();
    _keyFileCtrl.dispose();
    _privateKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickKeyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result?.files.single.path case final path?) {
        setState(() => _keyFileCtrl.text = path);
      }
    } catch (_) {
      // file picker cancelled or unavailable
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    String? privateKey = _privateKeyCtrl.text.trim().isEmpty ? null : _privateKeyCtrl.text.trim();

    // Load key from file if path provided but no inline key
    if (privateKey == null && _keyFileCtrl.text.trim().isNotEmpty) {
      try {
        final content = await File(_keyFileCtrl.text.trim()).readAsString();
        if (content.trim().isEmpty) throw Exception('Key file is empty');
        privateKey = content;
      } catch (e) {
        setState(() => _error = 'Could not read key file: $e');
        return;
      }
    }

    final host = SSHHost(
      id: widget.existing?.id ?? '',
      name: _nameCtrl.text.trim(),
      hostnameOrIp: _hostCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 22,
      keyId: _selectedKeyId,
      password: _passwordCtrl.text.isEmpty ? null : _passwordCtrl.text,
      keyFilePath: _keyFileCtrl.text.trim().isEmpty ? null : _keyFileCtrl.text.trim(),
      privateKey: privateKey,
    );

    if (mounted) Navigator.pop(context, host);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Host' : 'Add Host'),
        actions: [
          TextButton(
            onPressed: _submit,
            child: const Text('Save', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Connection'),
            _field(
              controller: _nameCtrl,
              label: 'Name',
              hint: 'My Server',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            _field(
              controller: _hostCtrl,
              label: 'Hostname / IP',
              hint: '192.168.1.1',
              keyboardType: TextInputType.url,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            _field(
              controller: _userCtrl,
              label: 'Username',
              hint: 'ubuntu',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            _field(
              controller: _portCtrl,
              label: 'Port',
              hint: '22',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 1 || n > 65535) return 'Enter a valid port (1–65535)';
                return null;
              },
            ),
            const SizedBox(height: 24),
            _section('Authentication'),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password (optional)',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.savedKeys.isNotEmpty) ...[
              DropdownButtonFormField<String?>(
                initialValue: _selectedKeyId,
                decoration: const InputDecoration(labelText: 'Saved Key (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ...widget.savedKeys.map(
                    (k) => DropdownMenuItem(
                      value: k.id,
                      child: Text(k.label ?? 'Key ${k.id.substring(0, 8)}'),
                    ),
                  ),
                ],
                onChanged: (val) => setState(() => _selectedKeyId = val),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _privateKeyCtrl,
              decoration: const InputDecoration(
                labelText: 'Private Key (PEM, optional)',
                hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _keyFileCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Key File Path (optional)'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Browse',
                  icon: const Icon(Icons.folder_open),
                  onPressed: _pickKeyFile,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Colors.tealAccent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: validator,
        ),
      );
}
