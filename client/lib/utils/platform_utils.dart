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

  /// Cached value so we only call the platform channel once.
  static double? _cachedInset;

  /// Initialise the traffic-light inset value at app start.
  /// Call once from `main()` before `runApp()` on macOS.
  static Future<void> initWindowChrome() async {
    if (!Platform.isMacOS) return;
    try {
      final raw = await _channel.invokeMethod<double>('trafficLightInset');
      _cachedInset = raw ?? 72.0;
    } catch (_) {
      _cachedInset = 72.0; // safe fallback while window is not yet ready
    }
  }

  /// Horizontal left inset needed to clear the macOS traffic-light buttons.
  /// Returns the value read from the OS (via [initWindowChrome]).
  /// Returns 0 on all non-macOS platforms.
  static double get trafficLightInset {
    if (!Platform.isMacOS) return 0;
    return _cachedInset ?? 72.0;
  }

  /// Returns [trafficLightInset] as a convenience for use inline in widgets.
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
