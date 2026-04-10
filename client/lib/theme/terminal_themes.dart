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

final terminalAppearances = <TerminalAppearance>[
  TerminalAppearance(
    key: 'tealDark',
    name: 'Teal Dark (default)',
    style: TerminalStyle.fromTextStyle(
      GoogleFonts.firaCode(fontSize: 14, height: 1.1, letterSpacing: 0),
    ),
    theme: TerminalTheme(
      background: Color(0xFF1D1F28),
      foreground: Color(0xFF00D1B2),
      cursor: Color(0xFF00D1B2),
      selection: Color(0xFF233042),
      black: Color(0xFF000000),
      red: Color(0xFFCC6666),
      green: Color(0xFFB5BD68),
      yellow: Color(0xFFF0C674),
      blue: Color(0xFF81A2BE),
      magenta: Color(0xFFB294BB),
      cyan: Color(0xFF8ABEB7),
      white: Color(0xFFECECEC),
      brightBlack: Color(0xFF6C6C6C),
      brightRed: Color(0xFFCC6666),
      brightGreen: Color(0xFFB5BD68),
      brightYellow: Color(0xFFF0C674),
      brightBlue: Color(0xFF81A2BE),
      brightMagenta: Color(0xFFB294BB),
      brightCyan: Color(0xFF8ABEB7),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFF233042),
      searchHitBackgroundCurrent: Color(0xFF2F3B52),
      searchHitForeground: Color(0xFF00D1B2),
    ),
  ),
  TerminalAppearance(
    key: 'solarizedDark',
    name: 'Solarized Dark',
    style: TerminalStyle.fromTextStyle(
      GoogleFonts.firaCode(fontSize: 14, height: 1.1, letterSpacing: 0),
    ),
    theme: TerminalTheme(
      background: Color(0xFF002B36),
      foreground: Color(0xFF839496),
      cursor: Color(0xFF93A1A1),
      selection: Color(0xFF073642),
      black: Color(0xFF073642),
      red: Color(0xFFDC322F),
      green: Color(0xFF859900),
      yellow: Color(0xFFB58900),
      blue: Color(0xFF268BD2),
      magenta: Color(0xFFD33682),
      cyan: Color(0xFF2AA198),
      white: Color(0xFFEEE8D5),
      brightBlack: Color(0xFF002B36),
      brightRed: Color(0xFFCB4B16),
      brightGreen: Color(0xFF586E75),
      brightYellow: Color(0xFF657B83),
      brightBlue: Color(0xFF839496),
      brightMagenta: Color(0xFF6C71C4),
      brightCyan: Color(0xFF93A1A1),
      brightWhite: Color(0xFFFDF6E3),
      searchHitBackground: Color(0xFF073642),
      searchHitBackgroundCurrent: Color(0xFF0A4B5C),
      searchHitForeground: Color(0xFFEEE8D5),
    ),
  ),
  TerminalAppearance(
    key: 'light',
    name: 'Light',
    style: TerminalStyle.fromTextStyle(
      GoogleFonts.firaCode(fontSize: 14, height: 1.1, letterSpacing: 0),
    ),
    theme: TerminalTheme(
      background: Color(0xFFFFFFFF),
      foreground: Color(0xFF000000),
      cursor: Color(0xFF000000),
      selection: Color(0xFFCCE5FF),
      black: Color(0xFF000000),
      red: Color(0xFFD70000),
      green: Color(0xFF5FAF00),
      yellow: Color(0xFFAF8700),
      blue: Color(0xFF0087FF),
      magenta: Color(0xFFAF00AF),
      cyan: Color(0xFF00AFAF),
      white: Color(0xFFD0D0D0),
      brightBlack: Color(0xFF808080),
      brightRed: Color(0xFFFF0000),
      brightGreen: Color(0xFF87D700),
      brightYellow: Color(0xFFFFAF00),
      brightBlue: Color(0xFF00AFFF),
      brightMagenta: Color(0xFFFF00FF),
      brightCyan: Color(0xFF00FFFF),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFFCCE5FF),
      searchHitBackgroundCurrent: Color(0xFFB3D7FF),
      searchHitForeground: Color(0xFF000000),
    ),
  ),
];

TerminalAppearance appearanceByKey(String? key) {
  return terminalAppearances.firstWhere(
    (a) => a.key == key,
    orElse: () => terminalAppearances.first,
  );
}
