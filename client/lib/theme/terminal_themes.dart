import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';
import 'package:google_fonts/google_fonts.dart';

class TerminalAppearance {
  final String key;
  final String name;
  final TerminalTheme theme;
  final TerminalStyle style;

  TerminalAppearance({
    required this.key,
    required this.name,
    required this.theme,
    required this.style,
  });
}

const double defaultTerminalFontSize = 14.0;

// Computed once — all themes share the same font settings.
final _sharedTerminalStyle = TerminalStyle.fromTextStyle(
  GoogleFonts.firaCode(fontSize: defaultTerminalFontSize, height: 1.1, letterSpacing: 0),
);

/// Returns a [TerminalStyle] at an arbitrary font size, preserving all other
/// font settings. Used by the pinch-to-zoom gesture in [TerminalPage].
TerminalStyle terminalStyleAtSize(double fontSize) => TerminalStyle.fromTextStyle(
      GoogleFonts.firaCode(fontSize: fontSize, height: 1.1, letterSpacing: 0),
    );

final terminalAppearances = <TerminalAppearance>[
  // ── Teal Dark (default) ───────────────────────────────────────────────────
  TerminalAppearance(
    key: 'tealDark',
    name: 'Teal Dark',
    style: _sharedTerminalStyle,
    theme: TerminalTheme(
      background: const Color(0xFF1D1F28),
      foreground: const Color(0xFF00D1B2),
      cursor: const Color(0xFF00D1B2),
      selection: const Color(0xFF233042),
      black: const Color(0xFF000000),
      red: const Color(0xFFCC6666),
      green: const Color(0xFFB5BD68),
      yellow: const Color(0xFFF0C674),
      blue: const Color(0xFF81A2BE),
      magenta: const Color(0xFFB294BB),
      cyan: const Color(0xFF8ABEB7),
      white: const Color(0xFFECECEC),
      brightBlack: const Color(0xFF6C6C6C),
      brightRed: const Color(0xFFCC6666),
      brightGreen: const Color(0xFFB5BD68),
      brightYellow: const Color(0xFFF0C674),
      brightBlue: const Color(0xFF81A2BE),
      brightMagenta: const Color(0xFFB294BB),
      brightCyan: const Color(0xFF8ABEB7),
      brightWhite: const Color(0xFFFFFFFF),
      searchHitBackground: const Color(0xFF233042),
      searchHitBackgroundCurrent: const Color(0xFF2F3B52),
      searchHitForeground: const Color(0xFF00D1B2),
    ),
  ),

  // ── Solarized Dark ────────────────────────────────────────────────────────
  TerminalAppearance(
    key: 'solarizedDark',
    name: 'Solarized Dark',
    style: _sharedTerminalStyle,
    theme: TerminalTheme(
      background: const Color(0xFF002B36),
      foreground: const Color(0xFF839496),
      cursor: const Color(0xFF93A1A1),
      selection: const Color(0xFF073642),
      black: const Color(0xFF073642),
      red: const Color(0xFFDC322F),
      green: const Color(0xFF859900),
      yellow: const Color(0xFFB58900),
      blue: const Color(0xFF268BD2),
      magenta: const Color(0xFFD33682),
      cyan: const Color(0xFF2AA198),
      white: const Color(0xFFEEE8D5),
      brightBlack: const Color(0xFF002B36),
      brightRed: const Color(0xFFCB4B16),
      brightGreen: const Color(0xFF586E75),
      brightYellow: const Color(0xFF657B83),
      brightBlue: const Color(0xFF839496),
      brightMagenta: const Color(0xFF6C71C4),
      brightCyan: const Color(0xFF93A1A1),
      brightWhite: const Color(0xFFFDF6E3),
      searchHitBackground: const Color(0xFF073642),
      searchHitBackgroundCurrent: const Color(0xFF0A4B5C),
      searchHitForeground: const Color(0xFFEEE8D5),
    ),
  ),

  // ── Dracula ───────────────────────────────────────────────────────────────
  TerminalAppearance(
    key: 'dracula',
    name: 'Dracula',
    style: _sharedTerminalStyle,
    theme: TerminalTheme(
      background: const Color(0xFF282A36),
      foreground: const Color(0xFFF8F8F2),
      cursor: const Color(0xFFF8F8F2),
      selection: const Color(0xFF44475A),
      black: const Color(0xFF21222C),
      red: const Color(0xFFFF5555),
      green: const Color(0xFF50FA7B),
      yellow: const Color(0xFFF1FA8C),
      blue: const Color(0xFFBD93F9),
      magenta: const Color(0xFFFF79C6),
      cyan: const Color(0xFF8BE9FD),
      white: const Color(0xFFF8F8F2),
      brightBlack: const Color(0xFF6272A4),
      brightRed: const Color(0xFFFF6E6E),
      brightGreen: const Color(0xFF69FF94),
      brightYellow: const Color(0xFFFFFFA5),
      brightBlue: const Color(0xFFD6ACFF),
      brightMagenta: const Color(0xFFFF92DF),
      brightCyan: const Color(0xFFA4FFFF),
      brightWhite: const Color(0xFFFFFFFF),
      searchHitBackground: const Color(0xFF44475A),
      searchHitBackgroundCurrent: const Color(0xFF6272A4),
      searchHitForeground: const Color(0xFFF8F8F2),
    ),
  ),

  // ── Nord ──────────────────────────────────────────────────────────────────
  TerminalAppearance(
    key: 'nord',
    name: 'Nord',
    style: _sharedTerminalStyle,
    theme: TerminalTheme(
      background: const Color(0xFF2E3440),
      foreground: const Color(0xFFD8DEE9),
      cursor: const Color(0xFFD8DEE9),
      selection: const Color(0xFF434C5E),
      black: const Color(0xFF3B4252),
      red: const Color(0xFFBF616A),
      green: const Color(0xFFA3BE8C),
      yellow: const Color(0xFFEBCB8B),
      blue: const Color(0xFF81A1C1),
      magenta: const Color(0xFFB48EAD),
      cyan: const Color(0xFF88C0D0),
      white: const Color(0xFFE5E9F0),
      brightBlack: const Color(0xFF4C566A),
      brightRed: const Color(0xFFBF616A),
      brightGreen: const Color(0xFFA3BE8C),
      brightYellow: const Color(0xFFEBCB8B),
      brightBlue: const Color(0xFF81A1C1),
      brightMagenta: const Color(0xFFB48EAD),
      brightCyan: const Color(0xFF8FBCBB),
      brightWhite: const Color(0xFFECEFF4),
      searchHitBackground: const Color(0xFF434C5E),
      searchHitBackgroundCurrent: const Color(0xFF4C566A),
      searchHitForeground: const Color(0xFFD8DEE9),
    ),
  ),

  // ── Monokai ───────────────────────────────────────────────────────────────
  TerminalAppearance(
    key: 'monokai',
    name: 'Monokai',
    style: _sharedTerminalStyle,
    theme: TerminalTheme(
      background: const Color(0xFF272822),
      foreground: const Color(0xFFF8F8F2),
      cursor: const Color(0xFFF8F8F0),
      selection: const Color(0xFF49483E),
      black: const Color(0xFF272822),
      red: const Color(0xFFF92672),
      green: const Color(0xFFA6E22E),
      yellow: const Color(0xFFF4BF75),
      blue: const Color(0xFF66D9E8),
      magenta: const Color(0xFFAE81FF),
      cyan: const Color(0xFFA1EFE4),
      white: const Color(0xFFF8F8F2),
      brightBlack: const Color(0xFF75715E),
      brightRed: const Color(0xFFF92672),
      brightGreen: const Color(0xFFA6E22E),
      brightYellow: const Color(0xFFF4BF75),
      brightBlue: const Color(0xFF66D9E8),
      brightMagenta: const Color(0xFFAE81FF),
      brightCyan: const Color(0xFFA1EFE4),
      brightWhite: const Color(0xFFF9F8F5),
      searchHitBackground: const Color(0xFF49483E),
      searchHitBackgroundCurrent: const Color(0xFF75715E),
      searchHitForeground: const Color(0xFFF8F8F2),
    ),
  ),

  // ── Light ─────────────────────────────────────────────────────────────────
  TerminalAppearance(
    key: 'light',
    name: 'Light',
    style: _sharedTerminalStyle,
    theme: TerminalTheme(
      background: const Color(0xFFFAFAFA),
      foreground: const Color(0xFF24292E),
      cursor: const Color(0xFF24292E),
      selection: const Color(0xFFD1ECF1),
      black: const Color(0xFF000000),
      red: const Color(0xFFD70000),
      green: const Color(0xFF5FAF00),
      yellow: const Color(0xFFAF8700),
      blue: const Color(0xFF0087FF),
      magenta: const Color(0xFFAF00AF),
      cyan: const Color(0xFF00AFAF),
      white: const Color(0xFFD0D0D0),
      brightBlack: const Color(0xFF808080),
      brightRed: const Color(0xFFFF0000),
      brightGreen: const Color(0xFF87D700),
      brightYellow: const Color(0xFFFFAF00),
      brightBlue: const Color(0xFF00AFFF),
      brightMagenta: const Color(0xFFFF00FF),
      brightCyan: const Color(0xFF00FFFF),
      brightWhite: const Color(0xFFFFFFFF),
      searchHitBackground: const Color(0xFFCCE5FF),
      searchHitBackgroundCurrent: const Color(0xFFB3D7FF),
      searchHitForeground: const Color(0xFF000000),
    ),
  ),
];

TerminalAppearance appearanceByKey(String? key) {
  return terminalAppearances.firstWhere(
    (a) => a.key == key,
    orElse: () => terminalAppearances.first,
  );
}
