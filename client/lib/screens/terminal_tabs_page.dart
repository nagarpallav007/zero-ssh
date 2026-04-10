import 'package:flutter/material.dart';
import '../models/ssh_host.dart';
import 'terminal_page.dart';
import 'host_management_page.dart';
import '../services/host_repository.dart';
import '../services/key_repository.dart';
import '../services/auth_service.dart';
import '../theme/terminal_themes.dart';

class TerminalTabsPage extends StatefulWidget {
  final HostRepository hostRepository;
  final String? userEmail;
  final bool loggedIn;
  final VoidCallback onLogout;
  final VoidCallback? onLogin; // for guest mode
  final KeyRepository keyRepository;
  final AuthService authService;
  final TerminalAppearance appearance;
  final void Function(TerminalAppearance) onAppearanceChanged;

  const TerminalTabsPage({
    super.key,
    required this.hostRepository,
    required this.keyRepository,
    required this.authService,
    required this.loggedIn,
    this.userEmail,
    required this.onLogout,
    this.onLogin,
    required this.appearance,
    required this.onAppearanceChanged,
  });

  @override
  State<TerminalTabsPage> createState() => _TerminalTabsPageState();
}

class _TabData {
  final String id;
  final String title;
  final SSHHost? host; // null → Hosts tab
  final Widget page;

  _TabData({required this.id, required this.title, required this.page, this.host});
}

class _TerminalTabsPageState extends State<TerminalTabsPage> {
  final _tabs = <_TabData>[];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _tabs.add(_buildHostsTab());
  }

  _TabData _buildHostsTab() => _TabData(
        id: 'hosts',
        title: 'Hosts',
        page: HostManagementPage(
          onHostOpen: _openSessionTab,
          hostRepository: widget.hostRepository,
          keyRepository: widget.keyRepository,
          loggedIn: widget.loggedIn,
          userEmail: widget.userEmail,
          onLogin: widget.onLogin,
        ),
      );

  void _openSessionTab(SSHHost host) {
    final existing = _tabs.indexWhere((t) => t.host?.id == host.id);
    if (existing != -1) {
      setState(() => _index = existing);
      return;
    }
    setState(() {
      _tabs.add(_TabData(
        id: host.id,
        title: host.name,
        host: host,
        page: TerminalPage(
          host: host,
          authService: widget.authService,
          appearance: widget.appearance,
        ),
      ));
      _index = _tabs.length - 1;
    });
  }

  void _closeTab(int i) {
    if (i == 0) return;
    setState(() {
      _tabs.removeAt(i);
      if (_index >= _tabs.length) _index = _tabs.length - 1;
      if (_index < 0) _index = 0;
    });
  }

  void _showAppearancePicker() async {
    final selected = await showModalBottomSheet<TerminalAppearance>(
      context: context,
      backgroundColor: const Color(0xFF1C1E2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Terminal Theme',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
            ...terminalAppearances.map(
              (a) => RadioListTile<TerminalAppearance>(
                title: Text(a.name),
                value: a,
                groupValue: widget.appearance,
                activeColor: const Color(0xFF20C997),
                onChanged: (val) => Navigator.of(ctx).pop(val),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) widget.onAppearanceChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            _TopBar(
              tabs: _tabs,
              activeIndex: _index,
              loggedIn: widget.loggedIn,
              userEmail: widget.userEmail,
              onTabTap: (i) => setState(() => _index = i),
              onTabClose: _closeTab,
              onNewTab: () => setState(() => _index = 0),
              onLogout: widget.onLogout,
              onLogin: widget.onLogin,
              onTheme: _showAppearancePicker,
            ),
            Expanded(
              child: Container(
                color: Colors.black,
                child: IndexedStack(
                  index: _index,
                  children: _tabs
                      .map((t) => KeyedSubtree(
                            key: PageStorageKey(t.id),
                            child: t.page,
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final List<_TabData> tabs;
  final int activeIndex;
  final bool loggedIn;
  final String? userEmail;
  final void Function(int) onTabTap;
  final void Function(int) onTabClose;
  final VoidCallback onNewTab;
  final VoidCallback onLogout;
  final VoidCallback? onLogin;
  final VoidCallback onTheme;

  const _TopBar({
    required this.tabs,
    required this.activeIndex,
    required this.loggedIn,
    required this.userEmail,
    required this.onTabTap,
    required this.onTabClose,
    required this.onNewTab,
    required this.onLogout,
    required this.onLogin,
    required this.onTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: Color(0xFF151720),
        border: Border(bottom: BorderSide(color: Color(0x18FFFFFF))),
      ),
      child: Row(
        children: [
          // Brand
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal_rounded, color: Color(0xFF20C997), size: 18),
                SizedBox(width: 6),
                Text(
                  'ZeroSSH',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),

          // Vertical divider
          const _VDivider(),

          // Scrollable tabs
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (int i = 0; i < tabs.length; i++)
                    _TabChip(
                      label: tabs[i].title,
                      isHosts: tabs[i].host == null,
                      active: i == activeIndex,
                      onTap: () => onTabTap(i),
                      onClose: i == 0 ? null : () => onTabClose(i),
                    ),
                ],
              ),
            ),
          ),

          // New tab
          _IconBtn(
            icon: Icons.add_rounded,
            tooltip: 'New tab',
            onTap: onNewTab,
          ),

          const _VDivider(),

          // Theme
          _IconBtn(
            icon: Icons.contrast_rounded,
            tooltip: 'Theme',
            onTap: onTheme,
          ),

          const _VDivider(),

          // Auth area
          if (loggedIn) ...[
            _UserArea(email: userEmail, onLogout: onLogout),
          ] else if (onLogin != null) ...[
            _SignInButton(onLogin: onLogin!),
          ],

          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: const Color(0x18FFFFFF),
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Icon(icon, size: 18, color: Colors.white54),
        ),
      ),
    );
  }
}

class _UserArea extends StatelessWidget {
  final String? email;
  final VoidCallback onLogout;

  const _UserArea({required this.email, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final display = email != null
        ? (email!.length > 20 ? '${email!.substring(0, 18)}…' : email!)
        : 'Account';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF20C997).withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF20C997).withOpacity(0.4)),
            ),
            child: const Icon(Icons.person_rounded, size: 14, color: Color(0xFF20C997)),
          ),
          const SizedBox(width: 6),
          Text(display, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Logout',
            child: InkWell(
              onTap: onLogout,
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.logout_rounded, size: 15, color: Colors.white38),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  final VoidCallback onLogin;
  const _SignInButton({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GestureDetector(
        onTap: onLogin,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF20C997).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF20C997).withOpacity(0.5)),
          ),
          child: const Text(
            'Sign In',
            style: TextStyle(
              color: Color(0xFF20C997),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tab chip ──────────────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String label;
  final bool isHosts;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _TabChip({
    required this.label,
    required this.isHosts,
    required this.active,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFF20C997);
    final bg = active
        ? activeColor.withOpacity(0.12)
        : Colors.transparent;
    final fg = active ? activeColor : Colors.white54;
    final border = active ? activeColor.withOpacity(0.5) : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isHosts ? Icons.dns_rounded : Icons.terminal_rounded,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Icon(Icons.close_rounded, size: 13, color: fg.withOpacity(0.7)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
