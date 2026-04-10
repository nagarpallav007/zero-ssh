import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process, File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_host.dart';
import '../services/auth_service.dart';
import '../theme/terminal_themes.dart';

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

  bool _connecting = true;
  bool _connected = false;
  String? _error;

  bool get _isLocal => widget.host.isLocal;

  @override
  void initState() {
    super.initState();

    _terminal = Terminal(
      maxLines: 20000,
      platform: Platform.isAndroid
          ? TerminalTargetPlatform.android
          : Platform.isIOS
              ? TerminalTargetPlatform.ios
              : Platform.isMacOS
                  ? TerminalTargetPlatform.macos
                  : Platform.isWindows
                      ? TerminalTargetPlatform.windows
                      : TerminalTargetPlatform.linux,
      onOutput: (data) => _sendInput(data),
      onResize: (w, h, _pw, _ph) {
        if (!_isLocal) {
          _session?.resizeTerminal(w, h);
        }
      },
    );

    _controller = TerminalController();
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      if (_isLocal) {
        _terminal.write('Starting local shell…\r\n');
        await _startLocalShell();
      } else {
        await _connectSsh(widget.host);
      }

      if (mounted) {
        setState(() {
          _connecting = false;
          _connected = true;
        });
      }
      _terminal.write('✓ Connected\r\n');
    } catch (e) {
      _terminal.write('✗ Connection failed: $e\r\n');
      if (mounted) {
        setState(() {
          _connecting = false;
          _connected = false;
          _error = e.toString();
        });
      }
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
    } else if ((h.keyFilePath ?? '').isNotEmpty) {
      final keyFile = File(h.keyFilePath!);
      if (!await keyFile.exists()) {
        throw Exception('Private key file not found: ${h.keyFilePath}');
      }
      keyPairs = SSHKeyPair.fromPem(
        await keyFile.readAsString(),
        (h.password?.isNotEmpty ?? false) ? h.password : null,
      );
    }

    _client = SSHClient(
      socket,
      username: h.username,
      identities: keyPairs,
      onPasswordRequest: () => h.password ?? '',
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
    final env = Map<String, String>.from(Platform.environment);
    env['TERM'] = env['TERM'] ?? 'xterm-256color';
    final process = await _spawnLocalProcess(shell, env);

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
      setState(() => _connected = false);
    }));
  }

  Future<Process> _spawnLocalProcess(_ShellCommand shell, Map<String, String> env) {
    if (Platform.isWindows) {
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
      return Process.start(
        shell.executable,
        args,
        environment: env,
      );
    });
  }

  _ShellCommand _detectLocalShell() {
    if (Platform.isWindows) {
      return _ShellCommand(executable: 'cmd.exe', args: []);
    }
    final envShell = Platform.environment['SHELL'];
    if (envShell != null && envShell.isNotEmpty) {
      return _ShellCommand(executable: envShell, args: ['-l']);
    }
    if (Platform.isMacOS || Platform.isLinux) {
      return _ShellCommand(executable: '/bin/bash', args: ['-l']);
    }
    return _ShellCommand(executable: '/bin/sh', args: ['-l']);
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
    if (mounted) setState(() => _connected = false);
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // for keep alive

    return Stack(
      children: [
        Positioned.fill(
          child: TerminalView(
            _terminal,
            controller: _controller,
            autofocus: true,
            autoResize: true,
            theme: widget.appearance.theme,
            textStyle: widget.appearance.style,
            cursorType: TerminalCursorType.block,
            hardwareKeyboardOnly: Platform.isMacOS,
            onSecondaryTapDown: (details, offset) async {
              final choice = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                  0,
                  0,
                ),
                items: const [
                  PopupMenuItem(value: 'paste', child: Text('Paste')),
                  PopupMenuItem(value: 'clear', child: Text('Clear')),
                ],
              );
              switch (choice) {
                case 'paste':
                  _pasteFromClipboard();
                  break;
                case 'clear':
                  _terminal.eraseDisplay();
                  break;
              }
            },
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              _connecting
                  ? 'Connecting…'
                  : (_connected ? 'Connected' : (_error != null ? 'Disconnected' : 'Idle')),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShellCommand {
  final String executable;
  final List<String> args;

  const _ShellCommand({
    required this.executable,
    required this.args,
  });
}
