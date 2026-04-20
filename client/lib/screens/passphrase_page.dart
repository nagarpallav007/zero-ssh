import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';

import '../models/workspace.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/crypto_service.dart';
import '../services/passphrase_manager.dart';
import '../services/workspace_repository.dart';
import '../theme/app_theme.dart';

/// Passphrase entry screen shown after login.
///
/// [isNewUser] = true  → "Create passphrase" mode (confirm field + strength bar).
/// [isNewUser] = false → "Enter passphrase" mode (single field).
///
/// On submit:
///   1. Argon2id(passphrase, userSalt) → master key → [PassphraseManager]
///   2. Keypair bootstrap: decrypt existing X25519 keypair or generate + upload
///   3. Default workspace key bootstrap: decrypt + cache or generate + upload
class PassphrasePage extends StatefulWidget {
  final bool isNewUser;
  final String userSalt;
  final AuthSession authSession;
  final ApiClient apiClient;
  final AuthService authService;
  final WorkspaceRepository workspaceRepository;
  final VoidCallback onPassphraseSet;

  const PassphrasePage({
    super.key,
    required this.isNewUser,
    required this.userSalt,
    required this.authSession,
    required this.apiClient,
    required this.authService,
    required this.workspaceRepository,
    required this.onPassphraseSet,
  });

  @override
  State<PassphrasePage> createState() => _PassphrasePageState();
}

class _PassphrasePageState extends State<PassphrasePage> {
  final _passphraseCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _deriving = false;
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
    if (s < 0.4) return AppColors.danger;
    if (s < 0.7) return AppColors.warning;
    return AppColors.success;
  }

  String _strengthLabel(double s) {
    if (s < 0.4) return 'Weak';
    if (s < 0.7) return 'Fair';
    return 'Strong';
  }

  Future<void> _submit() async {
    final p = _passphraseCtrl.text;
    if (p.length < 8) {
      setState(() => _error = 'Passphrase must be at least 8 characters');
      return;
    }
    if (widget.isNewUser && p != _confirmCtrl.text) {
      setState(() => _error = 'Passphrases do not match');
      return;
    }

    setState(() {
      _deriving = true;
      _error = null;
    });

    try {
      // Step 1 — Derive master key
      final masterKey = await CryptoService.deriveMasterKey(p, widget.userSalt);
      PassphraseManager.instance.setMasterKey(masterKey);

      // Step 2 — Keypair bootstrap
      final session = widget.authSession;
      final SimpleKeyPair keyPair;
      if (session.encryptedPrivateKey != null && session.publicKey != null) {
        // Decrypt existing private key with master key
        final privB64 =
            await CryptoService.decrypt(masterKey, session.encryptedPrivateKey!);
        final privBytes = base64.decode(privB64);
        final pubBytes = base64.decode(session.publicKey!);
        keyPair = SimpleKeyPairData(
          privBytes,
          publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        );
      } else {
        // Generate a new X25519 keypair and upload it
        keyPair = await CryptoService.generateKeyPair();
        final pub = await keyPair.extractPublicKey();
        final privData = await keyPair.extract();
        final pubB64 = base64.encode(pub.bytes);
        final privB64 = base64.encode(privData.bytes);
        final encPriv = await CryptoService.encrypt(masterKey, privB64);
        await widget.apiClient.putJson(
          '/auth/keypair',
          {'publicKey': pubB64, 'encryptedPrivateKey': encPriv},
          token: session.token,
        );
      }
      PassphraseManager.instance.setKeyPair(keyPair);

      // Step 3 — Default workspace key bootstrap
      // session.workspaces may be stale (empty) for users who were logged in
      // before the workspace migration. Fetch fresh from the API if needed.
      List<WorkspaceSession> workspaces = session.workspaces;
      if (workspaces.isEmpty) {
        try {
          final res = await widget.apiClient
              .getJson('/workspaces', token: session.token);
          workspaces = (res['workspaces'] as List<dynamic>? ?? [])
              .map((e) => WorkspaceSession.fromJson(e as Map<String, dynamic>))
              .toList();
          await widget.authService.saveWorkspacesCache(workspaces);
        } catch (_) {}
      }
      final defaultWs =
          workspaces.where((w) => w.isDefault).firstOrNull;
      if (defaultWs != null) {
        if (defaultWs.encryptedWorkspaceKey == null) {
          // First time: generate, ECIES-encrypt for self, upload
          final wsKey = CryptoService.generateWorkspaceKey();
          final pub = await keyPair.extractPublicKey();
          final wsKeyB64 = base64.encode(await wsKey.extractBytes());
          final encWsKey = await CryptoService.eciesEncrypt(pub, wsKeyB64);
          await widget.apiClient.putJson(
            '/auth/workspaces/${defaultWs.id}/key',
            {'encryptedWorkspaceKey': encWsKey},
            token: session.token,
          );
          widget.workspaceRepository.cacheWorkspaceKey(defaultWs.id, wsKey);
          // Persist the new encryptedWorkspaceKey so cold restarts can decrypt it
          await widget.authService.updateWorkspaceKeyCache(
              defaultWs.id, encWsKey);
        } else {
          // Decrypt existing workspace key and cache it
          await widget.workspaceRepository.getWorkspaceKey(
              defaultWs.id, defaultWs.encryptedWorkspaceKey!);
        }
      }

      widget.onPassphraseSet();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Failed to unlock. Check your passphrase and try again.';
          _deriving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final passphrase = _passphraseCtrl.text;
    final strength = _strength(passphrase);

    return Scaffold(
      backgroundColor: AppColors.surface0,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              color: AppColors.surface1,
              margin: const EdgeInsets.all(AppSpacing.lg),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(Icons.lock_outline_rounded, color: AppColors.accent, size: 26),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            widget.isNewUser
                                ? 'Create Encryption Passphrase'
                                : 'Enter Encryption Passphrase',
                            style: AppTypography.title,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Info box
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.accentBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Zero-Knowledge Security',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          const Text(
                            'Your SSH keys are encrypted on this device using your passphrase before being uploaded. '
                            'The server only stores encrypted data — it can never read your keys or host details. '
                            'Your passphrase never leaves this device.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Passphrase field
                    TextField(
                      controller: _passphraseCtrl,
                      obscureText: _obscure,
                      onChanged: (_) => setState(() {}),
                      textInputAction:
                          widget.isNewUser ? TextInputAction.next : TextInputAction.done,
                      onSubmitted: widget.isNewUser ? null : (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: widget.isNewUser ? 'New Passphrase' : 'Passphrase',
                        prefixIcon: const Icon(Icons.key_rounded, size: 18),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),

                    // Strength indicator
                    if (widget.isNewUser && passphrase.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      LinearProgressIndicator(
                        value: strength,
                        color: _strengthColor(strength),
                        backgroundColor: AppColors.border,
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _strengthLabel(strength),
                        style: TextStyle(color: _strengthColor(strength), fontSize: 12),
                      ),
                    ],

                    // Confirm field
                    if (widget.isNewUser) ...[
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _confirmCtrl,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Confirm Passphrase',
                          prefixIcon: Icon(Icons.key_rounded, size: 18),
                        ),
                      ),
                    ],

                    // Error
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),

                    // Submit
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _deriving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _deriving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Text(
                                widget.isNewUser ? 'Set Passphrase' : 'Unlock',
                                style:
                                    const TextStyle(fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),

                    // Warning
                    if (widget.isNewUser) ...[
                      const SizedBox(height: AppSpacing.md),
                      const Text(
                        'Remember this passphrase — it cannot be recovered. '
                        'Without it, your encrypted data cannot be decrypted.',
                        style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                            height: 1.5),
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
