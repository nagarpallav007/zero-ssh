import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

/// Centralized platform detection — replaces scattered `Platform.is*` calls.
abstract final class PlatformUtils {
  static final bool isDesktop =
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static final bool isMobile = Platform.isIOS || Platform.isAndroid;

  static final bool isWindows = Platform.isWindows;

  static final bool isMacOS = Platform.isMacOS;

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

  // ── macOS traffic-light clearance ────────────────────────────────────────

  static const _channel = MethodChannel('com.zerossh/window_chrome');

  /// Cached values — set once at startup, never change.
  static double? _cachedInset;
  static double? _cachedTitlebarHeight;

  /// Read actual traffic-light inset and titlebar height from the OS.
  /// Call once from `main()` on macOS before `runApp()`.
  static Future<void> initWindowChrome() async {
    if (!Platform.isMacOS) return;
    try {
      final results = await Future.wait([
        _channel.invokeMethod<double>('trafficLightInset'),
        _channel.invokeMethod<double>('titlebarHeight'),
      ]);
      _cachedInset = results[0] ?? 72.0;
      _cachedTitlebarHeight = results[1] ?? 28.0;
    } catch (_) {
      _cachedInset = 72.0;
      _cachedTitlebarHeight = 28.0;
    }
  }

  /// Horizontal left inset to clear the macOS traffic-light buttons.
  /// Returns 0 on non-macOS.
  static double get trafficLightInset {
    if (!Platform.isMacOS) return 0;
    return _cachedInset ?? 72.0;
  }

  /// Height of the native macOS titlebar — use this for the Flutter top bar
  /// so the traffic lights land exactly at vertical center.
  /// Returns 0 on non-macOS (no inset needed elsewhere).
  static double get nativeTitlebarHeight {
    if (!Platform.isMacOS) return 0;
    return _cachedTitlebarHeight ?? 28.0;
  }

  /// Convenience for widgets.
  static double titleBarInset(BuildContext context) => trafficLightInset;

  /// Maps the current platform to the xterm TerminalTargetPlatform enum.
  static TerminalTargetPlatform get terminalPlatform {
    if (Platform.isAndroid) return TerminalTargetPlatform.android;
    if (Platform.isIOS) return TerminalTargetPlatform.ios;
    if (Platform.isMacOS) return TerminalTargetPlatform.macos;
    if (Platform.isWindows) return TerminalTargetPlatform.windows;
    return TerminalTargetPlatform.linux;
  }
}
