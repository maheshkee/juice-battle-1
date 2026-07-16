import 'package:flutter/material.dart';

class PlayerControls extends StatefulWidget {
  final bool         enabled;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onVolUp;
  final VoidCallback onVolDown;

  const PlayerControls({
    super.key,
    required this.enabled,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onVolUp,
    required this.onVolDown,
  });

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  bool _playing = true;

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

        // ── Label ────────────────────────────────────────────────────────────
        const Row(children: [
          Icon(Icons.tune_rounded, color: Color(0xFF4A5568), size: 16),
          SizedBox(width: 8),
          Text('CONTROLS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A5568),
              letterSpacing: 1.5,
            )),
        ]),

        const SizedBox(height: 14),

        // ── Pause / Resume — full width ───────────────────────────────────────
        _bigBtn(
          label: _playing ? '⏸   PAUSE' : '▶   RESUME',
          color: const Color(0xFF00E5FF),
          onTap: () {
            if (!widget.enabled) return;
            setState(() => _playing = !_playing);
            _playing ? widget.onResume() : widget.onPause();
          },
        ),

        const SizedBox(height: 8),

        // ── Vol down | Stop | Vol up ──────────────────────────────────────────
        Row(children: [
          Expanded(child: _iconBtn(
            icon: Icons.volume_down_rounded,
            color: const Color(0xFF7C4DFF),
            onTap: widget.onVolDown,
          )),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: _labelIconBtn(
            icon:  Icons.stop_rounded,
            label: 'STOP',
            color: const Color(0xFFFF3D71),
            onTap: () {
              if (!widget.enabled) return;
              setState(() => _playing = true);
              widget.onStop();
            },
          )),
          const SizedBox(width: 8),
          Expanded(child: _iconBtn(
            icon: Icons.volume_up_rounded,
            color: const Color(0xFF7C4DFF),
            onTap: widget.onVolUp,
          )),
        ]),

      ]),
    );
  }

  // ── Button helpers ────────────────────────────────────────────────────────

  Widget _bigBtn({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: widget.enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: widget.enabled
            ? color.withOpacity(0.12)
            : const Color(0xFF1E2A3A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.enabled
              ? color.withOpacity(0.4)
              : const Color(0xFF1E2A3A),
          ),
          boxShadow: widget.enabled
            ? [BoxShadow(
                color: color.withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, 3),
              )]
            : null,
        ),
        child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: widget.enabled ? color : const Color(0xFF4A5568),
            letterSpacing: 1,
          )),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: widget.enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: widget.enabled
            ? color.withOpacity(0.12)
            : const Color(0xFF1E2A3A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.enabled
              ? color.withOpacity(0.4)
              : const Color(0xFF1E2A3A),
          ),
        ),
        child: Icon(icon,
          color: widget.enabled ? color : const Color(0xFF4A5568),
          size: 22),
      ),
    );
  }

  Widget _labelIconBtn({
    required IconData  icon,
    required String    label,
    required Color     color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: widget.enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: widget.enabled
            ? color.withOpacity(0.12)
            : const Color(0xFF1E2A3A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.enabled
              ? color.withOpacity(0.4)
              : const Color(0xFF1E2A3A),
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon,
            color: widget.enabled ? color : const Color(0xFF4A5568),
            size: 18),
          const SizedBox(width: 6),
          Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: widget.enabled ? color : const Color(0xFF4A5568),
            )),
        ]),
      ),
    );
  }
}
