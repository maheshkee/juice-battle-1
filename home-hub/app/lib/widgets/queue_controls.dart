import 'package:flutter/material.dart';
import '../services/board_state.dart';

class QueueControls extends StatelessWidget {
  final bool       enabled;
  final QueueState queueState;
  final VoidCallback onPlay;
  final VoidCallback onReplay;
  final VoidCallback onSkip;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  const QueueControls({
    super.key,
    required this.enabled,
    required this.queueState,
    required this.onPlay,
    required this.onReplay,
    required this.onSkip,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = queueState.status == 'playing';
    final isPaused  = queueState.status == 'paused';
    final isActive  = isPlaying || isPaused;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header + status
        Row(children: [
          const Icon(Icons.playlist_play, color: Color(0xFFFF0000), size: 18),
          const SizedBox(width: 8),
          const Text('QUEUE CONTROLS',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: Colors.white70, letterSpacing: 1.5,
            )),
          const Spacer(),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isPlaying
                    ? const Color(0xFFFF0000).withOpacity(0.15)
                    : Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isPlaying ? 'PLAYING ${queueState.currentIndex + 1}/${queueState.total}'
                          : 'PAUSED',
                style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700,
                  color: isPlaying ? const Color(0xFFFF0000) : Colors.orange,
                  letterSpacing: 1,
                )),
            ),
        ]),

        if (isActive && queueState.title.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(queueState.title,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
            overflow: TextOverflow.ellipsis),
        ],

        const SizedBox(height: 14),

        // Main controls row
        Row(children: [
          _btn(
            icon: Icons.play_arrow,
            label: 'PLAY',
            onTap: enabled && !isActive ? onPlay : null,
            primary: true,
          ),
          const SizedBox(width: 8),
          _btn(
            icon: isPaused ? Icons.play_circle : Icons.pause_circle,
            label: isPaused ? 'RESUME' : 'PAUSE',
            onTap: enabled && isActive ? (isPaused ? onResume : onPause) : null,
          ),
          const SizedBox(width: 8),
          _btn(
            icon: Icons.skip_next,
            label: 'SKIP',
            onTap: enabled && isPlaying ? onSkip : null,
          ),
          const SizedBox(width: 8),
          _btn(
            icon: Icons.replay,
            label: 'REPLAY',
            onTap: enabled && isActive ? onReplay : null,
          ),
          const SizedBox(width: 8),
          _btn(
            icon: Icons.stop_circle_outlined,
            label: 'STOP',
            onTap: enabled && isActive ? onStop : null,
            danger: true,
          ),
        ]),
      ]),
    );
  }

  Widget _btn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
    bool danger  = false,
  }) {
    final color = danger   ? const Color(0xFFFF3D71)
                : primary  ? const Color(0xFFFF0000)
                : const Color(0xFF4A90D9);
    final enabled = onTap != null;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: enabled ? color.withOpacity(0.12) : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enabled ? color.withOpacity(0.4) : Colors.white.withOpacity(0.05)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18,
              color: enabled ? color : Colors.white24),
            const SizedBox(height: 3),
            Text(label,
              style: TextStyle(
                fontSize: 8, fontWeight: FontWeight.w700,
                color: enabled ? color : Colors.white24,
                letterSpacing: 0.5,
              )),
          ]),
        ),
      ),
    );
  }
}
