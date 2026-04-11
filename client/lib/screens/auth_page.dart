import 'dart:convert';

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class AuthPage extends StatefulWidget {
  final AuthService authService;
  final void Function({bool isNew}) onAuthenticated;
  final VoidCallback onSkip;

  const AuthPage({
    super.key,
    required this.authService,
    required this.onAuthenticated,
    required this.onSkip,
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isLogin = true;
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// Parses a server error string into a human-readable message.
  /// Handles ApiException bodies like {"error":{"password":["Must be at least 8 characters"]}}
  String _parseError(Object e) {
    final raw = e.toString();
    // Strip 'ApiException(NNN): ' prefix if present
    final bodyStart = raw.indexOf('{');
    if (bodyStart == -1) return raw;
    try {
      final body = jsonDecode(raw.substring(bodyStart)) as Map<String, dynamic>;
      final err = body['error'];
      if (err is String) return err;
      if (err is Map) {
        // e.g. {"password": ["msg1", "msg2"], "email": ["msg3"]}
        final messages = <String>[];
        err.forEach((field, value) {
          if (value is List) {
            messages.addAll(value.map((m) => m.toString()));
          } else if (value is String) {
            messages.add(value);
          }
        });
        if (messages.isNotEmpty) return messages.join('\n');
      }
    } catch (_) {}
    return raw;
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isLogin) {
        await widget.authService.login(email, password);
        if (mounted) widget.onAuthenticated(isNew: false);
      } else {
        await widget.authService.signup(email, password);
        if (mounted) widget.onAuthenticated(isNew: true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _parseError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.terminal_rounded, color: AppColors.accent, size: 26),
                        const SizedBox(width: AppSpacing.sm),
                        Text('ZeroSSH', style: AppTypography.heading),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Tab toggle
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        children: [
                          _Tab(label: 'Login', active: _isLogin, onTap: () => setState(() => _isLogin = true)),
                          _Tab(label: 'Sign Up', active: !_isLogin, onTap: () => setState(() => _isLogin = false)),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Email
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Password
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _loading ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                        helperText: _isLogin ? null : 'Minimum 8 characters',
                        helperStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 18,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),

                    // Error
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),

                    // Submit
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : Text(
                                _isLogin ? 'Log In' : 'Create Account',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Skip
                    TextButton(
                      onPressed: _loading ? null : widget.onSkip,
                      style: TextButton.styleFrom(foregroundColor: AppColors.textTertiary),
                      child: const Text('Continue without account'),
                    ),
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

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.surface3 : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? AppColors.textPrimary : AppColors.textTertiary,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
