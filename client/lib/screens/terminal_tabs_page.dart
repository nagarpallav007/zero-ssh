import 'package:flutter/material.dart';

import '../models/ssh_host.dart';
import '../services/auth_service.dart';
import '../services/host_repository.dart';
import '../services/key_repository.dart';
import '../theme/app_theme.dart';
import '../theme/terminal_themes.dart';
import '../utils/platform_utils.dart';
import 'host_management_page.dart';
import 'terminal_page.dart';

// ── Tab model ─────────────────────────────────────────────────────────────────

class _TabData {
  final String id;
  final String title;
  final SSHHost? host; // null → Hosts tab

  /// Per-tab terminal appearance. Null for the Hosts tab.
  TerminalAppearance? appearance;

  _TabData({required this.id, required this.title, this.host, this.appearance});
}

// ── Page widget ───────────────────────────────────────────────────────────────

class TerminalTabsPage extends StatefulWidget {
  final HostRepository hostRepository;
  final KeyRepository keyRepository;
  final AuthService authService;
  final bool loggedIn;
  final String? userEmail;
  final VoidCallback onLogout;
  final VoidCallback? onLogin; // non-null in guest mode
  final TerminalAppearance defaultAppearance;
  final void Function(TerminalAppearance) onDefaultAppearanceChanged;

  const TerminalTabsPage({
    super.key,
    required this.hostRepository,
    required this.keyRepository,
    required this.authService,
    required this.loggedIn,
    this.userEmail,
    required this.onLogout,
    this.onLogin,
    required this.defaultAppearance,
    required this.onDefaultAppearanceChanged,
  });

  @override
  State<TerminalTabsPage> createState() => _TerminalTabsPageState();
}

class _TerminalTabsPageState extends State<TerminalTabsPage> {
  final _tabs = <_TabData>[];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _tabs.add(_TabData(id: 'hosts', title: 'Hosts'));
  }

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
        appearance: widget.defaultAppearance,
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

  /// Opens the appearance picker. Applies to the current terminal tab.
  /// If Hosts tab is active, changes the default for new tabs.
  void _showAppearancePicker() async {
    final currentTab = _tabs[_index];
    final current = currentTab.appearance ?? widget.defaultAppearance;

    final selected = await showModalBottomSheet<TerminalAppearance>(
      context: context,
      builder: (ctx) => _ThemePicker(current: current),
    );
    if (selected == null || !mounted) return;

    if (currentTab.host != null) {
      // Apply to this tab only
      setState(() => currentTab.appearance = selected);
    } else {
      // Hosts tab: change the default for new tabs
      widget.onDefaultAppearanceChanged(selected);
    }
  }

  // Build the content widget for a tab — done dynamically so appearance changes
  // propagate to TerminalPage via didUpdateWidget / build re-runs.
  Widget _buildTabContent(_TabData tab) {
    if (tab.host == null) {
      return HostManagementPage(
        onHostOpen: _openSessionTab,
        hostRepository: widget.hostRepository,
        keyRepository: widget.keyRepository,
        loggedIn: widget.loggedIn,
        userEmail: widget.userEmail,
        onLogin: widget.onLogin,
      );
    }
    return TerminalPage(
      host: tab.host!,
      authService: widget.authService,
      appearance: tab.appearance ?? widget.defaultAppearance,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppBreakpoints.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface0,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            _TopBar(
              tabs: _tabs,
              activeIndex: _index,
              layout: layout,
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
              child: IndexedStack(
                index: _index,
                children: _tabs
                    .map((t) => KeyedSubtree(
                          key: PageStorageKey(t.id),
                          child: _buildTabContent(t),
                        ))
                    .toList(),
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
  final LayoutClass layout;
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
    required this.layout,
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
    final compact = layout == LayoutClass.compact;

    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.surface1,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // ── Traffic light clearance (macOS) + Brand ──
          SizedBox(width: PlatformUtils.titleBarInset(context)),
          _BrandMark(compact: compact),

          if (!compact) const _VDivider(),

          // ── Scrollable tabs + add button ──
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
              child: Row(
                children: [
                  for (int i = 0; i < tabs.length; i++)
                    _TabChip(
                      label: tabs[i].title,
                      isHosts: tabs[i].host == null,
                      active: i == activeIndex,
                      compact: compact,
                      onTap: () => onTabTap(i),
                      onClose: i == 0 ? null : () => onTabClose(i),
                    ),
                  // + button sits right after last tab
                  _AddTabBtn(onTap: onNewTab, compact: compact),
                ],
              ),
            ),
          ),

          // ── Right actions ──
          if (!compact) const _VDivider(),
          _IconBtn(
            icon: Icons.contrast_rounded,
            tooltip: 'Terminal theme',
            onTap: onTheme,
          ),
          const _VDivider(),
          if (loggedIn)
            _UserArea(email: userEmail, onLogout: onLogout)
          else if (onLogin != null)
            _SignInButton(onLogin: onLogin!),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }
}

// ── Brand mark ────────────────────────────────────────────────────────────────

class _BrandMark extends StatelessWidget {
  final bool compact;
  const _BrandMark({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.terminal_rounded, color: AppColors.accent, size: 16),
          if (!compact) ...[
            const SizedBox(width: 6),
            const Text(
              'ZeroSSH',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Vertical divider ──────────────────────────────────────────────────────────

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      color: AppColors.border,
      margin: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
}

// ── Icon button ───────────────────────────────────────────────────────────────

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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: 14),
          child: Icon(icon, size: 17, color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

// ── Add tab button ────────────────────────────────────────────────────────────

class _AddTabBtn extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;
  const _AddTabBtn({required this.onTap, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'New tab',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.sm : AppSpacing.md,
            vertical: 14,
          ),
          child: const Icon(Icons.add_rounded, size: 17, color: AppColors.textTertiary),
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
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _TabChip({
    required this.label,
    required this.isHosts,
    required this.active,
    required this.compact,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.accent : AppColors.textTertiary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 3, vertical: 6),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.sm : AppSpacing.md,
          vertical: 0,
        ),
        decoration: BoxDecoration(
          color: active ? AppColors.surface3 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isHosts ? Icons.dns_rounded : Icons.terminal_rounded,
              size: 13,
              color: fg,
            ),
            if (!compact || active) ...[
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
            if (onClose != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 12, color: fg.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── User area (avatar → popup) ────────────────────────────────────────────────

class _UserArea extends StatelessWidget {
  final String? email;
  final VoidCallback onLogout;

  const _UserArea({required this.email, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Tooltip(
        message: 'Account',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showMenu(context),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accentMuted,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accentBorder),
            ),
            child: const Icon(Icons.person_rounded, size: 14, color: AppColors.accent),
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;

    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        offset.dx + size.width,
        0,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 2),
          child: Text(
            email ?? 'Account',
            style: AppTypography.caption,
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: 'logout',
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 2),
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 15, color: AppColors.danger),
              SizedBox(width: AppSpacing.sm + 2),
              Text('Log out', style: TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ),
        ),
      ],
    );

    if (choice == 'logout') onLogout();
  }
}

// ── Sign-in button (guest mode) ───────────────────────────────────────────────

class _SignInButton extends StatelessWidget {
  final VoidCallback onLogin;
  const _SignInButton({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: GestureDetector(
        onTap: onLogin,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.accentMuted,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.accentBorder),
          ),
          child: const Text(
            'Sign In',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Theme picker bottom sheet ─────────────────────────────────────────────────

class _ThemePicker extends StatelessWidget {
  final TerminalAppearance current;
  const _ThemePicker({required this.current});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: Text('Terminal Theme', style: AppTypography.title),
          ),
          ...terminalAppearances.map((a) {
            final isSelected = a.key == current.key;
            return ListTile(
              dense: true,
              leading: _ThemePreview(appearance: a),
              title: Text(a.name, style: AppTypography.body),
              trailing: isSelected
                  ? const Icon(Icons.check_rounded, color: AppColors.accent, size: 18)
                  : null,
              onTap: () => Navigator.of(context).pop(a),
            );
          }),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  final TerminalAppearance appearance;
  const _ThemePreview({required this.appearance});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 26,
      decoration: BoxDecoration(
        color: Color(appearance.theme.background.toARGB32()),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        child: Text(
          '>_',
          style: TextStyle(
            color: Color(appearance.theme.foreground.toARGB32()),
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
