import 'package:flutter/material.dart';

class PlayerControls extends StatefulWidget {
  final bool enabled;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onMute;
  final VoidCallback onUnmute;
  final VoidCallback onVolUp;
  final VoidCallback onVolDown;

  const PlayerControls({super.key, required this.enabled, required this.onPause,
    required this.onResume, required this.onStop, required this.onMute,
    required this.onUnmute, required this.onVolUp, required this.onVolDown});

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  bool _playing = true;
  bool _muted   = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.gamepad, color: Color(0xFF4A5568), size: 16),
          SizedBox(width: 8),
          Text('PLAYER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: Color(0xFF4A5568), letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _btn(
            label: _playing ? '⏸  PAUSE' : '▶  RESUME',
            color: const Color(0xFF00E5FF),
            onTap: () {
              setState(() => _playing = !_playing);
              _playing ? widget.onResume() : widget.onPause();
            },
          )),
          const SizedBox(width: 8),
          Expanded(child: _btn(
            label: _muted ? '🔊  UNMUTE' : '🔇  MUTE',
            color: const Color(0xFFFFAB00),
            onTap: () {
              setState(() => _muted = !_muted);
              _muted ? widget.onMute() : widget.onUnmute();
            },
          )),
          const SizedBox(width: 8),
          Expanded(child: _btn(
            label: '⏹  STOP',
            color: const Color(0xFFFF3D71),
            onTap: () {
              setState(() { _playing = true; _muted = false; });
              widget.onStop();
            },
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _btn(
            label: '🔉  VOL DOWN',
            color: const Color(0xFF7C4DFF),
            onTap: widget.onVolDown,
          )),
          const SizedBox(width: 8),
          Expanded(child: _btn(
            label: '🔊  VOL UP',
            color: const Color(0xFF7C4DFF),
            onTap: widget.onVolUp,
          )),
        ]),
      ]),
    );
  }

  Widget _btn({required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: widget.enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: widget.enabled ? color.withOpacity(0.12) : const Color(0xFF1E2A3A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: widget.enabled ? color.withOpacity(0.4) : const Color(0xFF1E2A3A)),
        ),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
            color: widget.enabled ? color : const Color(0xFF4A5568))),
      ),
    );
  }
}
