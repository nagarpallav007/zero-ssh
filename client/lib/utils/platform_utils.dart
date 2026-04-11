import 'dart:io' show Platform;
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

/// Centralized platform detection — replaces scattered `Platform.is*` calls.
abstract final class PlatformUtils {
  static final bool isDesktop =
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static final bool isMobile = Platform.isIOS || Platform.isAndroid;

  static final bool isWindows = Platform.isWindows;

  /// Desktop platforms always have a physical keyboard.
  /// Fixes the old bug where only macOS got `hardwareKeyboardOnly: true`.
  static final bool hasPhysicalKeyboard = isDesktop;

  /// Local shell (Process.start) is only available on desktop.
  static final bool supportsLocalShell = isDesktop;

  /// Returns the local OS username, or null on mobile.
  static String? get localUsername {
    if (isMobile) return null;
    return Platform.environment['USER'] ??
        Platform.environment['USERNAME'] ??
        'local';
  }

  /// The machine's hostname; 'localhost' on mobile.
  static String get localHostname {
    if (isMobile) return 'localhost';
    return Platform.localHostname;
  }

  /// Left inset to clear the macOS traffic-light buttons.
  /// Returns 0 on all other platforms (including mobile).
  static double titleBarInset(BuildContext context) {
    if (!Platform.isMacOS) return 0;
    // macOS traffic lights occupy roughly 80px on the left
    return 80;
  }

  /// Maps the current platform to the xterm TerminalTargetPlatform enum.
  static TerminalTargetPlatform get terminalPlatform {
    if (Platform.isAndroid) return TerminalTargetPlatform.android;
    if (Platform.isIOS) return TerminalTargetPlatform.ios;
    if (Platform.isMacOS) return TerminalTargetPlatform.macos;
    if (Platform.isWindows) return TerminalTargetPlatform.windows;
    return TerminalTargetPlatform.linux;
  }
}
