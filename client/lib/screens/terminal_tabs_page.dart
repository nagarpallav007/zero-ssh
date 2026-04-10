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
    required this.appearance,
    required this.onAppearanceChanged,
  });
  @override
  State<TerminalTabsPage> createState() => _TerminalTabsPageState();
}

class _TabData {
  final String id;
  final String title;
  final IconData icon;
  final SSHHost? host; // null => Hosts screen
  final Widget page;
  _TabData({
    required this.id,
    required this.title,
    required this.icon,
    required this.page,
    this.host,
  });
}

class _TerminalTabsPageState extends State<TerminalTabsPage> {
  final _tabs = <_TabData>[];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _openHostsTab(); // left-most fixed "SSH Hosts" tab
  }

  void _openHostsTab() {
    // Only insert once
    if (_tabs.where((t) => t.id == 'hosts').isEmpty) {
      _tabs.insert(
        0,
        _TabData(
          id: 'hosts',
          title: 'SSH Hosts',
          icon: Icons.storage_rounded,
          // IMPORTANT: pass callback so clicking a host opens a session tab
          page: HostManagementPage(
            pickMode: true, // hide its AppBar, it lives inside tabs
            onHostOpen: _openSessionTab,
            hostRepository: widget.hostRepository,
            keyRepository: widget.keyRepository,
            loggedIn: widget.loggedIn,
            userEmail: widget.userEmail,
          ),
          host: null,
        ),
      );
    }
    _index = 0;
  }

  void _openSessionTab(SSHHost host) {
    // If already open, just focus it
    final existing = _tabs.indexWhere((t) => t.host?.id == host.id);
    if (existing != -1) {
      setState(() => _index = existing);
      return;
    }
    setState(() {
          _tabs.add(
            _TabData(
              id: host.id,
              title: host.name,
              icon: Icons.terminal_rounded,
              page: TerminalPage(host: host, authService: widget.authService, appearance: widget.appearance),
              host: host,
            ),
          );
          _index = _tabs.length - 1;
        });
  }

  void _closeTab(int i) {
    if (i == 0) return; // keep Hosts tab
    setState(() {
      _tabs.removeAt(i);
      if (_index >= _tabs.length) _index = _tabs.length - 1;
      if (_index < 0) _index = 0;
    });
  }

  void _showAppearancePicker() async {
    final selected = await showModalBottomSheet<TerminalAppearance>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text('Terminal Appearance', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ...terminalAppearances.map(
                (a) => RadioListTile<TerminalAppearance>(
                  title: Text(a.name),
                  value: a,
                  groupValue: widget.appearance,
                  onChanged: (val) => Navigator.of(ctx).pop(val),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      widget.onAppearanceChanged(selected);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final shellBg = const Color(0xFF0E0F12);
    final tabBarBg = const Color(0xFF151720);

    return Scaffold(
      backgroundColor: shellBg,
      body: SafeArea(
        top: true, bottom: false,
        child: Column(
          children: [
            // Top Tab Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: tabBarBg,
                border: const Border(
                  bottom: BorderSide(color: Color(0x22FFFFFF)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  )
                ],
              ),
              child: Row(
                children: [
                  // Tabs (scrollable if many)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (int i = 0; i < _tabs.length; i++)
                            _TabChip(
                              label: _tabs[i].title,
                              icon: _tabs[i].icon,
                              active: i == _index,
                              onTap: () => setState(() => _index = i),
                              onClose: i == 0 ? null : () => _closeTab(i),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Appearance',
                    icon: const Icon(Icons.palette, color: Colors.white),
                    onPressed: _showAppearancePicker,
                  ),
                  const SizedBox(width: 4),
                  if (widget.loggedIn && widget.userEmail != null) ...[
                    Text(
                      widget.userEmail!,
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: widget.onLogout,
                      icon: const Icon(Icons.logout, size: 18, color: Colors.white),
                      label: const Text('Logout', style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // New Tab → jumps to Hosts picker
                  TextButton.icon(
                    onPressed: () => setState(() => _index = 0),
                    icon: const Icon(Icons.add, size: 18, color: Colors.white),
                    label: const Text('New Tab', style: TextStyle(color: Colors.white)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0x2222FF99),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),

            // Content: keep children mounted so sessions don't reconnect
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

class _TabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _TabChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active ? const Color(0xFF20C997) : const Color(0x3326C6DA);
    final fg = active ? Colors.black : Colors.white.withOpacity(0.95);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          hoverColor: active ? Colors.white24 : Colors.white10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? const Color(0xFF20C997) : const Color(0x22FFFFFF),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                if (onClose != null) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onClose,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(Icons.close_rounded, size: 16, color: fg.withOpacity(0.9)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
