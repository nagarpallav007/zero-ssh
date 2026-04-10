import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ssh_host.dart';
import '../models/ssh_key.dart';
import '../services/key_repository.dart';

enum _AuthMode { none, password, sshKey }

/// Full-screen form for adding or editing an SSH host.
///
/// All key data is stored in the keys table — no inline private keys on hosts.
/// When the user adds a new key from this form, it is saved to the keys table
/// immediately and the returned keyId is stored on the host.
///
/// Returns the completed [SSHHost] via [Navigator.pop] or null on cancel.
class HostFormPage extends StatefulWidget {
  final SSHHost? existing;
  final List<SSHKey> savedKeys;
  final KeyRepository? keyRepository; // null in guest mode (SSH key auth hidden)

  const HostFormPage({
    super.key,
    this.existing,
    required this.savedKeys,
    this.keyRepository,
  });

  @override
  State<HostFormPage> createState() => _HostFormPageState();
}

class _HostFormPageState extends State<HostFormPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _labelCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _passwordCtrl;

  _AuthMode _authMode = _AuthMode.none;
  String? _selectedKeyId;
  List<SSHKey> _keys = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    _labelCtrl = TextEditingController(text: h?.name ?? '');
    _hostCtrl = TextEditingController(text: h?.hostnameOrIp ?? '');
    _userCtrl = TextEditingController(text: h?.username ?? '');
    _portCtrl = TextEditingController(text: (h?.port ?? 22).toString());
    _passwordCtrl = TextEditingController(text: h?.password ?? '');
    _keys = List.of(widget.savedKeys);

    if (h != null) {
      if (h.keyId != null) {
        _authMode = _AuthMode.sshKey;
        _selectedKeyId = h.keyId;
      } else if (h.password != null && h.password!.isNotEmpty) {
        _authMode = _AuthMode.password;
      }
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _hostCtrl.dispose();
    _userCtrl.dispose();
    _portCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final host = SSHHost(
      id: widget.existing?.id ?? '',
      name: _labelCtrl.text.trim(),
      hostnameOrIp: _hostCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 22,
      password: _authMode == _AuthMode.password && _passwordCtrl.text.isNotEmpty
          ? _passwordCtrl.text
          : null,
      keyId: _authMode == _AuthMode.sshKey ? _selectedKeyId : null,
    );

    Navigator.of(context).pop(host);
  }

  // ── Add new key inline ────────────────────────────────────────────────────

  Future<void> _addNewKey() async {
    final result = await showModalBottomSheet<SSHKey>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1E2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AddKeySheet(keyRepository: widget.keyRepository!),
    );

    if (result != null && mounted) {
      setState(() {
        _keys.add(result);
        _selectedKeyId = result.id;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151720),
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        leadingWidth: 80,
        title: Text(
          isNew ? 'New Host' : 'Edit Host',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      color: Color(0xFF20C997),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          children: [
            _Section(
              children: [
                _Field(
                  label: 'Label',
                  controller: _labelCtrl,
                  hint: 'My Server',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Label is required' : null,
                ),
                _Field(
                  label: 'Hostname / IP',
                  controller: _hostCtrl,
                  hint: '192.168.1.1',
                  keyboardType: TextInputType.url,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Hostname is required' : null,
                ),
                _Field(
                  label: 'Username',
                  controller: _userCtrl,
                  hint: 'root',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Username is required' : null,
                ),
                _Field(
                  label: 'Port',
                  controller: _portCtrl,
                  hint: '22',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    final p = int.tryParse(v ?? '');
                    if (p == null || p < 1 || p > 65535) return 'Enter a valid port (1–65535)';
                    return null;
                  },
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _SectionHeader(label: 'AUTHENTICATION'),
            _Section(
              children: [
                _AuthModeRow(
                  mode: _authMode,
                  canUseSshKey: widget.keyRepository != null,
                  onChanged: (m) => setState(() {
                    _authMode = m;
                    if (m != _AuthMode.sshKey) _selectedKeyId = null;
                    if (m != _AuthMode.password) _passwordCtrl.clear();
                  }),
                ),
                if (_authMode == _AuthMode.password)
                  _Field(
                    label: 'Password',
                    controller: _passwordCtrl,
                    hint: '••••••••',
                    obscureText: true,
                    isLast: true,
                  ),
                if (_authMode == _AuthMode.sshKey) ...[
                  _KeyDropdownRow(
                    keys: _keys,
                    selectedId: _selectedKeyId,
                    onChanged: (id) => setState(() => _selectedKeyId = id),
                    onAddNew: _addNewKey,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white38,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final List<Widget> children;
  const _Section({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF151720),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final bool isLast;

  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  validator: validator,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: Colors.white24),
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    errorStyle: const TextStyle(fontSize: 11),
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(height: 1, indent: 16, color: Color(0x18FFFFFF)),
      ],
    );
  }
}

class _AuthModeRow extends StatelessWidget {
  final _AuthMode mode;
  final bool canUseSshKey;
  final ValueChanged<_AuthMode> onChanged;

  const _AuthModeRow({
    required this.mode,
    required this.canUseSshKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Text('Method', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const Spacer(),
          _ModeChip(
            label: 'None',
            active: mode == _AuthMode.none,
            onTap: () => onChanged(_AuthMode.none),
          ),
          const SizedBox(width: 8),
          _ModeChip(
            label: 'Password',
            active: mode == _AuthMode.password,
            onTap: () => onChanged(_AuthMode.password),
          ),
          if (canUseSshKey) ...[
            const SizedBox(width: 8),
            _ModeChip(
              label: 'SSH Key',
              active: mode == _AuthMode.sshKey,
              onTap: () => onChanged(_AuthMode.sshKey),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF20C997) : const Color(0xFF1E2029),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? const Color(0xFF20C997) : const Color(0x30FFFFFF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _KeyDropdownRow extends StatelessWidget {
  final List<SSHKey> keys;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final VoidCallback onAddNew;

  const _KeyDropdownRow({
    required this.keys,
    required this.selectedId,
    required this.onChanged,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 1, indent: 16, color: Color(0x18FFFFFF)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const SizedBox(
                width: 100,
                child: Text('Key', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: selectedId,
                    isExpanded: true,
                    alignment: AlignmentDirectional.centerEnd,
                    dropdownColor: const Color(0xFF1C1E2A),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    hint: const Text(
                      'Select a key',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                      textAlign: TextAlign.right,
                    ),
                    items: [
                      ...keys.map((k) => DropdownMenuItem(
                            value: k.id,
                            child: Text(
                              k.label ?? 'Key ${k.id.substring(0, 6)}',
                              textAlign: TextAlign.right,
                            ),
                          )),
                    ],
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: 16, color: Color(0x18FFFFFF)),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const Icon(Icons.add_circle_outline, color: Color(0xFF20C997), size: 20),
          title: const Text(
            'Add new key…',
            style: TextStyle(color: Color(0xFF20C997), fontSize: 14),
          ),
          onTap: onAddNew,
        ),
      ],
    );
  }
}

// ── Add Key bottom sheet ───────────────────────────────────────────────────────

class _AddKeySheet extends StatefulWidget {
  final KeyRepository keyRepository;
  const _AddKeySheet({required this.keyRepository});

  @override
  State<_AddKeySheet> createState() => _AddKeySheetState();
}

class _AddKeySheetState extends State<_AddKeySheet> {
  final _labelCtrl = TextEditingController();
  final _pemCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _pemCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        final content = await File(result.files.single.path!).readAsString();
        setState(() => _pemCtrl.text = content.trim());
        // Pre-fill label with filename (no extension)
        if (_labelCtrl.text.isEmpty) {
          final filename = result.files.single.name.replaceAll(RegExp(r'\.[^.]+$'), '');
          _labelCtrl.text = filename;
        }
      }
    } catch (e) {
      setState(() => _error = 'Could not read file: $e');
    }
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    final pem = _pemCtrl.text.trim();
    if (label.isEmpty || pem.isEmpty) {
      setState(() => _error = 'Label and key content are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final key = await widget.keyRepository.addKey(label, pem);
      if (mounted) Navigator.of(context).pop(key);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add SSH Key',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _labelCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Key label',
              hintText: 'e.g. Personal MacBook',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pemCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Private key (PEM)',
              hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Load from file'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF20C997),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('Save Key', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
