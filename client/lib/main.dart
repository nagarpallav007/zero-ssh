import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/auth_page.dart';
import 'screens/passphrase_page.dart';
import 'screens/terminal_tabs_page.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/host_repository.dart';
import 'services/key_repository.dart';
import 'services/passphrase_manager.dart';
import 'theme/app_theme.dart';
import 'theme/terminal_themes.dart';

void main() {
  runApp(const ProviderScope(child: ZeroSSHApp()));
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

  // Default appearance for new tabs (persisted in SharedPreferences)
  late TerminalAppearance _defaultAppearance = terminalAppearances.first;

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
    final needsPassphrase = sess != null && !PassphraseManager.instance.isSet;
    setState(() {
      _session = sess;
      _booting = false;
      _defaultAppearance = appearanceByKey(savedKey);
      _passphraseReady = !needsPassphrase;
      _isFirstLogin = false;
    });
  }

  void _onAuthenticated({bool isNew = false}) async {
    final sess = await _authService.currentSession();
    setState(() {
      _session = sess;
      _guestMode = false;
      _passphraseReady = false;
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

  void _onPassphraseSet() => setState(() => _passphraseReady = true);

  void _onRequestLogin() => setState(() => _guestMode = false);

  void _onDefaultAppearanceChanged(TerminalAppearance a) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('terminal_appearance', a.key);
    setState(() => _defaultAppearance = a);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZeroSSH',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_booting) {
      return Scaffold(
        backgroundColor: AppColors.surface0,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_guestMode) return _mainTabs();

    if (_session == null) {
      return AuthPage(
        authService: _authService,
        onAuthenticated: ({bool isNew = false}) => _onAuthenticated(isNew: isNew),
        onSkip: () => setState(() => _guestMode = true),
      );
    }

    if (!_passphraseReady) {
      return PassphrasePage(
        isNewUser: _isFirstLogin,
        onPassphraseSet: _onPassphraseSet,
      );
    }

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
      onLogin: _guestMode ? _onRequestLogin : null,
      defaultAppearance: _defaultAppearance,
      onDefaultAppearanceChanged: _onDefaultAppearanceChanged,
    );
  }
}
