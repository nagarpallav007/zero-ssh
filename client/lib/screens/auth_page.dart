import 'package:flutter/material.dart';
import '../services/auth_service.dart';

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
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
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
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.terminal, color: Colors.tealAccent, size: 28),
                        SizedBox(width: 10),
                        Text(
                          'ZeroSSH',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ToggleButtons(
                      isSelected: [_isLogin, !_isLogin],
                      onPressed: (i) => setState(() => _isLogin = i == 0),
                      children: const [
                        Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Login')),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Sign Up')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        child: Text(_isLogin ? 'Login' : 'Create Account'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading ? null : widget.onSkip,
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
