import 'package:flutter/material.dart';
import '../services/passphrase_manager.dart';

/// Passphrase entry screen shown after login.
///
/// [isNewUser] = true  → "Create passphrase" mode (confirm field + strength bar).
/// [isNewUser] = false → "Enter passphrase" mode (single field).
///
/// On success, stores the passphrase in [PassphraseManager] and calls [onPassphraseSet].
class PassphrasePage extends StatefulWidget {
  final bool isNewUser;
  final VoidCallback onPassphraseSet;

  const PassphrasePage({
    super.key,
    required this.isNewUser,
    required this.onPassphraseSet,
  });

  @override
  State<PassphrasePage> createState() => _PassphrasePageState();
}

class _PassphrasePageState extends State<PassphrasePage> {
  final _passphraseCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passphraseCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  double _strength(String p) {
    if (p.isEmpty) return 0;
    double score = 0;
    if (p.length >= 12) score += 0.25;
    if (p.length >= 20) score += 0.15;
    if (RegExp(r'[A-Z]').hasMatch(p)) score += 0.15;
    if (RegExp(r'[a-z]').hasMatch(p)) score += 0.15;
    if (RegExp(r'[0-9]').hasMatch(p)) score += 0.15;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score += 0.15;
    return score.clamp(0.0, 1.0);
  }

  Color _strengthColor(double s) {
    if (s < 0.4) return Colors.redAccent;
    if (s < 0.7) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  void _submit() {
    final p = _passphraseCtrl.text;
    if (p.length < 8) {
      setState(() => _error = 'Passphrase must be at least 8 characters');
      return;
    }
    if (widget.isNewUser && p != _confirmCtrl.text) {
      setState(() => _error = 'Passphrases do not match');
      return;
    }
    PassphraseManager.instance.set(p);
    widget.onPassphraseSet();
  }

  @override
  Widget build(BuildContext context) {
    final passphrase = _passphraseCtrl.text;
    final strength = _strength(passphrase);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              color: const Color(0xFF151720),
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_outline, color: Colors.tealAccent, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          widget.isNewUser ? 'Create Encryption Passphrase' : 'Enter Encryption Passphrase',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Zero-Knowledge Security',
                            style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Your SSH keys are encrypted on this device using your passphrase before being uploaded. '
                            'The server only stores encrypted data — it can never read your keys or host details. '
                            'Your passphrase never leaves this device.',
                            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passphraseCtrl,
                      obscureText: _obscure,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: widget.isNewUser ? 'New Passphrase' : 'Passphrase',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (widget.isNewUser && passphrase.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: strength,
                        color: _strengthColor(strength),
                        backgroundColor: Colors.white12,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strength < 0.4
                            ? 'Weak'
                            : strength < 0.7
                                ? 'Fair'
                                : 'Strong',
                        style: TextStyle(color: _strengthColor(strength), fontSize: 12),
                      ),
                    ],
                    if (widget.isNewUser) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmCtrl,
                        obscureText: _obscure,
                        decoration: const InputDecoration(labelText: 'Confirm Passphrase'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(widget.isNewUser ? 'Set Passphrase' : 'Unlock'),
                      ),
                    ),
                    if (widget.isNewUser) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Remember this passphrase — it cannot be recovered. '
                        'Without it, your encrypted data cannot be decrypted.',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
