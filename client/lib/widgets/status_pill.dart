import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  final bool connecting;
  final bool connected;
  final String? error;

  const StatusPill({
    super.key,
    required this.connecting,
    required this.connected,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final label = connecting
        ? 'Connecting…'
        : connected
            ? 'Connected'
            : error != null
                ? 'Disconnected'
                : 'Idle';

    final color = connecting
        ? Colors.orangeAccent
        : connected
            ? Colors.greenAccent
            : Colors.white54;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
