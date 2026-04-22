import 'package:flutter/material.dart';

class LedModeBar extends StatelessWidget {
  final bool ledOn;
  final String mode;
  final bool enabled;
  final VoidCallback onLedToggle;
  final VoidCallback onModeIdle;
  final VoidCallback onModeYT;
  final VoidCallback onModeClock;

  const LedModeBar({super.key, required this.ledOn, required this.mode, required this.enabled,
    required this.onLedToggle, required this.onModeIdle, required this.onModeYT, required this.onModeClock});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: enabled ? onLedToggle : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: ledOn ? const Color(0xFFFFD600).withOpacity(0.15) : const Color(0xFF1E2A3A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ledOn ? const Color(0xFFFFD600).withOpacity(0.5) : const Color(0xFF2A3A4A)),
              boxShadow: ledOn ? [BoxShadow(color: const Color(0xFFFFD600).withOpacity(0.3), blurRadius: 12)] : [],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lightbulb, color: ledOn ? const Color(0xFFFFD600) : const Color(0xFF4A5568), size: 18),
              const SizedBox(width: 6),
              Text(ledOn ? 'ON' : 'OFF',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1,
                  color: ledOn ? const Color(0xFFFFD600) : const Color(0xFF4A5568))),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Row(children: [
          _modeBtn('IDLE',  mode == 'idle',    enabled, onModeIdle,  const Color(0xFF4A9EFF)),
          const SizedBox(width: 6),
          _modeBtn('YT',   mode == 'youtube',  enabled, onModeYT,    const Color(0xFFFF0000)),
          const SizedBox(width: 6),
          _modeBtn('CLOCK',mode == 'clock',    enabled, onModeClock, const Color(0xFF7C4DFF)),
        ])),
      ]),
    );
  }

  Widget _modeBtn(String label, bool active, bool enabled, VoidCallback onTap, Color color) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.2) : const Color(0xFF1E2A3A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? color.withOpacity(0.6) : const Color(0xFF2A3A4A)),
          ),
          child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1,
              color: active ? color : const Color(0xFF4A5568))),
        ),
      ),
    );
  }
}
