import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_host.dart';
import '../services/auth_service.dart';
import '../theme/terminal_themes.dart';
import '../utils/platform_utils.dart';

class TerminalPage extends StatefulWidget {
  final SSHHost host;
  final AuthService authService;
  final TerminalAppearance appearance;
  const TerminalPage({
    super.key,
    required this.host,
    required this.authService,
    required this.appearance,
  });

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late Terminal _terminal;
  late final TerminalController _controller;

  SSHClient? _client;
  SSHSession? _session;
  Process? _localProcess;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;

  bool get _isLocal => widget.host.isLocal;

  @override
  void initState() {
    super.initState();

    _terminal = Terminal(
      maxLines: 20000,
      platform: PlatformUtils.terminalPlatform,
      onOutput: (data) => _sendInput(data),
      onResize: (w, h, pw, ph) {
        if (!_isLocal) _session?.resizeTerminal(w, h);
      },
    );

    _controller = TerminalController();
    _connect();
  }

  Future<void> _connect() async {
    try {
      if (_isLocal) {
        if (!PlatformUtils.supportsLocalShell) {
          _terminal.write('Local shell is not supported on this platform.\r\n');
          return;
        }
        _terminal.write('Starting local shell…\r\n');
        await _startLocalShell();
      } else {
        await _connectSsh(widget.host);
      }
      _terminal.write('✓ Connected\r\n');
    } catch (e) {
      _terminal.write('✗ Connection failed: $e\r\n');
    }
  }

  Future<void> _connectSsh(SSHHost h) async {
    _terminal.write('Connecting to ${h.username}@${h.hostnameOrIp}:${h.port} …\r\n');

    final socket = await SSHSocket.connect(
      h.hostnameOrIp,
      h.port,
      timeout: const Duration(seconds: 12),
    );

    List<SSHKeyPair>? keyPairs;
    if ((h.privateKey ?? '').isNotEmpty) {
      keyPairs = SSHKeyPair.fromPem(
        h.privateKey!,
        (h.password?.isNotEmpty ?? false) ? h.password : null,
      );
    }

    final hasPassword = h.password != null && h.password!.isNotEmpty;
    if (keyPairs == null && !hasPassword) {
      throw Exception(
        'No authentication method available.\n'
        'Add a password or an SSH key to this host.',
      );
    }

    _client = SSHClient(
      socket,
      username: h.username,
      identities: keyPairs,
      onPasswordRequest: hasPassword ? () => h.password! : null,
    );

    _session = await _client!.shell(
      pty: SSHPtyConfig(
        width: _terminal.viewWidth > 0 ? _terminal.viewWidth : 80,
        height: _terminal.viewHeight > 0 ? _terminal.viewHeight : 24,
      ),
    );

    _stdoutSub = _session!.stdout.listen((data) {
      _terminal.write(const Utf8Decoder().convert(data));
    });
    _stderrSub = _session!.stderr.listen((data) {
      _terminal.write(const Utf8Decoder().convert(data));
    });

    _session!.write(const Utf8Encoder().convert('\r'));
  }

  Future<void> _startLocalShell() async {
    final shell = _detectLocalShell();
    final process = await _spawnLocalProcess(shell);

    _localProcess = process;
    _stdoutSub = process.stdout.listen((data) {
      _terminal.write(const Utf8Decoder().convert(data));
    });
    _stderrSub = process.stderr.listen((data) {
      _terminal.write(const Utf8Decoder().convert(data));
    });

    unawaited(process.exitCode.then((code) {
      if (!mounted) return;
      _terminal.write('\r\n[local shell exited ($code)]\r\n');
      _terminal.write('\r\n[Reconnect to continue]\r\n');
    }));
  }

  Future<Process> _spawnLocalProcess(_ShellCommand shell) {
    final env = Map<String, String>.from(Platform.environment)
      ..['TERM'] = Platform.environment['TERM'] ?? 'xterm-256color';

    if (PlatformUtils.isWindows) {
      return Process.start(
        shell.executable,
        shell.args,
        environment: env,
        runInShell: true,
      );
    }

    return Process.start(
      'script',
      ['-q', '/dev/null', shell.executable, ...shell.args],
      environment: env,
    ).catchError((_) {
      final args = List<String>.from(shell.args);
      if (!args.contains('-i')) args.add('-i');
      return Process.start(shell.executable, args, environment: env);
    });
  }

  _ShellCommand _detectLocalShell() {
    if (PlatformUtils.isWindows) {
      return const _ShellCommand(executable: 'cmd.exe', args: []);
    }
    final envShell = Platform.environment['SHELL'];
    if (envShell != null && envShell.isNotEmpty) {
      return _ShellCommand(executable: envShell, args: const ['-l']);
    }
    return const _ShellCommand(executable: '/bin/bash', args: ['-l']);
  }

  void _sendInput(String data) {
    if (_isLocal) {
      _localProcess?.stdin.add(utf8.encode(data));
    } else {
      _session?.write(utf8.encode(data));
    }
  }

  Future<void> _disconnect() async {
    try {
      await _stdoutSub?.cancel();
      await _stderrSub?.cancel();
    } catch (_) {}
    _stdoutSub = null;
    _stderrSub = null;
    if (_isLocal) {
      try {
        _localProcess?.kill();
      } catch (_) {}
      _localProcess = null;
    } else {
      try {
        await _session?.done;
      } catch (_) {}
      _session = null;
      try {
        _client?.close();
        await _client?.done;
      } catch (_) {}
      _client = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disconnect();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _terminal.paste(data.text!);
    }
  }

  Future<void> _showContextMenu(Offset globalPosition) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPosition.dx, globalPosition.dy, 0, 0),
      items: const [
        PopupMenuItem(value: 'paste', child: Text('Paste')),
        PopupMenuItem(value: 'clear', child: Text('Clear')),
      ],
    );
    switch (choice) {
      case 'paste':
        _pasteFromClipboard();
      case 'clear':
        _terminal.eraseDisplay();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // for keep alive

    final terminalView = TerminalView(
      _terminal,
      controller: _controller,
      autofocus: true,
      autoResize: true,
      theme: widget.appearance.theme,
      textStyle: widget.appearance.style,
      cursorType: TerminalCursorType.block,
      hardwareKeyboardOnly: PlatformUtils.hasPhysicalKeyboard,
      onSecondaryTapDown: (details, offset) =>
          _showContextMenu(details.globalPosition),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: PlatformUtils.isMobile
              ? GestureDetector(
                  onLongPressStart: (details) =>
                      _showContextMenu(details.globalPosition),
                  child: terminalView,
                )
              : terminalView,
        ),
      ],
    );
  }
}

class _ShellCommand {
  final String executable;
  final List<String> args;

  const _ShellCommand({required this.executable, required this.args});
}
