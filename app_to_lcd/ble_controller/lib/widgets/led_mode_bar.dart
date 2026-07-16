import 'package:flutter/material.dart';

class LedModeBar extends StatefulWidget {
  final bool ledOn;
  final String mode;
  final bool enabled;
  final VoidCallback onLedToggle;
  final VoidCallback onModeIdle;
  final VoidCallback onModeClock;
  final VoidCallback onSchedule;
  final VoidCallback onWhistle;

  const LedModeBar({super.key,
    required this.ledOn, required this.mode, required this.enabled,
    required this.onLedToggle, required this.onModeIdle,
    required this.onModeClock, required this.onSchedule,
    required this.onWhistle});

  @override
  State<LedModeBar> createState() => _LedModeBarState();
}

class _LedModeBarState extends State<LedModeBar>
    with TickerProviderStateMixin {

  late AnimationController _idlePulse;
  late AnimationController _clockPulse;
  late Animation<double> _idleAnim;
  late Animation<double> _clockAnim;

  @override
  void initState() {
    super.initState();
    _idlePulse  = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 1200));
    _clockPulse = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 1200));

    _idleAnim  = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _idlePulse,  curve: Curves.easeInOut));
    _clockAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _clockPulse, curve: Curves.easeInOut));

    _syncAnimations();
  }

  @override
  void didUpdateWidget(LedModeBar old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) {
      _syncAnimations();
    }
  }

  void _syncAnimations() {
    if (widget.mode == 'idle') {
      _idlePulse.repeat(reverse: true);
    } else {
      _idlePulse.stop();
      _idlePulse.value = 0.5;
    }
    if (widget.mode == 'clock') {
      _clockPulse.repeat(reverse: true);
    } else {
      _clockPulse.stop();
      _clockPulse.value = 0.5;
    }
  }

  @override
  void dispose() {
    _idlePulse.dispose();
    _clockPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E3048))),
      child: Row(children: [
        Expanded(child: _buildModeBtn(
          label: 'IDLE',
          icon: Icons.hourglass_bottom_rounded,
          active: widget.mode == 'idle',
          color: const Color(0xFF7C3AED),
          pulseAnim: _idleAnim,
          onTap: widget.enabled ? widget.onModeIdle : null)),
        const SizedBox(width: 7),
        Expanded(child: _buildModeBtn(
          label: 'CLOCK',
          icon: Icons.access_time_rounded,
          active: widget.mode == 'clock',
          color: const Color(0xFF0EA5E9),
          pulseAnim: _clockAnim,
          onTap: widget.enabled ? widget.onModeClock : null)),
        const SizedBox(width: 7),
        _buildSchedBtn(),
        const SizedBox(width: 7),
        _buildWhistleBtn(),
      ]),
    );
  }

  Widget _buildModeBtn({
    required String label,
    required IconData icon,
    required bool active,
    required Color color,
    required Animation<double> pulseAnim,
    required VoidCallback? onTap,
  }) =>
    GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: pulseAnim,
        builder: (_, __) => AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active
              ? color.withOpacity(0.15 + pulseAnim.value * 0.08)
              : const Color(0xFF111D2E),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: active
                ? color.withOpacity(0.5 + pulseAnim.value * 0.3)
                : color.withOpacity(0.15),
              width: active ? 1.5 : 1),
            boxShadow: active ? [
              BoxShadow(
                color: color.withOpacity(pulseAnim.value * 0.35),
                blurRadius: 12,
                offset: const Offset(0, 2))
            ] : []),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedScale(
              scale: active ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: Icon(icon, size: 16,
                color: active ? color : color.withOpacity(0.3))),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700,
              color: active ? color : color.withOpacity(0.3),
              letterSpacing: 0.5)),
          ]),
        ),
      ),
    );

  Widget _buildSchedBtn() {
    const color = Color(0xFFFF9F0A);
    return GestureDetector(
      onTap: widget.onSchedule,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 8, offset: const Offset(0, 2))
          ]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_month_rounded, size: 16, color: color),
          const SizedBox(height: 4),
          const Text('SCHED', style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700,
            color: color, letterSpacing: 0.5)),
        ]),
      ),
    );
  }

  Widget _buildWhistleBtn() {
    const color = Color(0xFF00E5FF);
    return GestureDetector(
      onTap: widget.onWhistle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 8, offset: const Offset(0, 2))
          ]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📣', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 2),
          const Text('WHISTLE', style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700,
            color: color, letterSpacing: 0.5)),
        ]),
      ),
    );
  }
}
