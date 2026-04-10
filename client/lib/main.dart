import 'package:flutter/material.dart';

import 'screens/auth_page.dart';
import 'screens/passphrase_page.dart';
import 'screens/terminal_tabs_page.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/host_repository.dart';
import 'services/key_repository.dart';
import 'services/passphrase_manager.dart';
import 'theme/terminal_themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const ZeroSSHApp());
}

class ZeroSSHApp extends StatefulWidget {
  const ZeroSSHApp({super.key});

  @override
  State<ZeroSSHApp> createState() => _ZeroSSHAppState();
}

class _ZeroSSHAppState extends State<ZeroSSHApp> {
  late final ApiClient _apiClient = ApiClient(onUnauthorized: _onLogout);
  late final AuthService _authService = AuthService(apiClient: _apiClient);
  late final HostRepository _hostRepository =
      HostRepository(apiClient: _apiClient, authService: _authService);
  late final KeyRepository _keyRepository =
      KeyRepository(apiClient: _apiClient, authService: _authService);
  late TerminalAppearance _appearance = terminalAppearances.first;

  AuthSession? _session;
  bool _booting = true;
  bool _guestMode = false;
  bool _passphraseReady = false;
  bool _isFirstLogin = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final sess = await _authService.currentSession();
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('terminal_appearance');
    // On app restart, passphrase must be re-entered (never persisted).
    final needsPassphrase = sess != null && !PassphraseManager.instance.isSet;
    setState(() {
      _session = sess;
      _booting = false;
      _appearance = appearanceByKey(savedKey);
      _passphraseReady = !needsPassphrase;
      _isFirstLogin = false; // returning user who bootstrapped a saved session
    });
  }

  void _onAuthenticated({bool isNew = false}) async {
    final sess = await _authService.currentSession();
    setState(() {
      _session = sess;
      _guestMode = false;
      _passphraseReady = false; // force passphrase prompt
      _isFirstLogin = isNew;
    });
  }

  Future<void> _onLogout() async {
    PassphraseManager.instance.clear();
    await _authService.logout();
    setState(() {
      _session = null;
      _guestMode = false;
      _passphraseReady = false;
      _isFirstLogin = false;
    });
  }

  void _onPassphraseSet() {
    setState(() => _passphraseReady = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZeroSSH',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E0F12),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF1E2029),
          border: OutlineInputBorder(),
          labelStyle: TextStyle(color: Colors.white70),
        ),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Guest mode — skip auth and passphrase; no sync available
    if (_guestMode) {
      return _mainTabs();
    }

    // Not authenticated → show auth page
    if (_session == null) {
      return AuthPage(
        authService: _authService,
        onAuthenticated: ({bool isNew = false}) => _onAuthenticated(isNew: isNew),
        onSkip: () => setState(() => _guestMode = true),
      );
    }

    // Authenticated but passphrase not entered yet → show passphrase page
    if (!_passphraseReady) {
      return PassphrasePage(
        isNewUser: _isFirstLogin,
        onPassphraseSet: _onPassphraseSet,
      );
    }

    // Authenticated + passphrase set → show main app
    return _mainTabs();
  }

  Widget _mainTabs() {
    return TerminalTabsPage(
      hostRepository: _hostRepository,
      keyRepository: _keyRepository,
      authService: _authService,
      loggedIn: _session != null,
      userEmail: _session?.email,
      onLogout: _onLogout,
      appearance: _appearance,
      onAppearanceChanged: _updateAppearance,
    );
  }

  void _updateAppearance(TerminalAppearance a) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('terminal_appearance', a.key);
    setState(() {
      _appearance = a;
    });
  }
}
