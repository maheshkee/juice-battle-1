import 'package:flutter/material.dart';

class PlayerControls extends StatefulWidget {
  final bool enabled;
  final String? nowPlaying;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onMute;
  final VoidCallback onUnmute;
  final VoidCallback onVolUp;
  final VoidCallback onVolDown;
  final VoidCallback onSeekForward;
  final VoidCallback onSeekBack;
  final VoidCallback onReplay;
  final Function(String) onQuality;

  const PlayerControls({super.key,
    required this.enabled,
    this.nowPlaying,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onMute,
    required this.onUnmute,
    required this.onVolUp,
    required this.onVolDown,
    required this.onSeekForward,
    required this.onSeekBack,
    required this.onReplay,
    required this.onQuality,
  });

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls>
    with SingleTickerProviderStateMixin {
  bool _playing = true;
  bool _muted   = false;
  String _quality = 'Auto';
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const _bg      = Color(0xFF0D1520);
  static const _surface = Color(0xFF162030);
  static const _border  = Color(0xFF1E3048);
  static const _blue    = Color(0xFF3B82F6);
  static const _cyan    = Color(0xFF06B6D4);
  static const _red     = Color(0xFFEF4444);
  static const _amber   = Color(0xFFF59E0B);
  static const _purple  = Color(0xFF8B5CF6);
  static const _dimmed  = Color(0xFF4B6070);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500));
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    if (widget.nowPlaying != null) _pulseCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PlayerControls old) {
    super.didUpdateWidget(old);
    if (widget.nowPlaying != null && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (widget.nowPlaying == null && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 16),
          decoration: BoxDecoration(
            color: _border, borderRadius: BorderRadius.circular(2))),
        const Text('Video Quality', style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 8),
        ...['Auto', '1080p', '720p', '480p', '360p', '240p', '144p']
          .map((q) => ListTile(
            title: Text(q, style: TextStyle(
              fontSize: 15,
              color: _quality == q ? _blue : Colors.white,
              fontWeight: _quality == q
                ? FontWeight.w700 : FontWeight.w400)),
            trailing: _quality == q
              ? const Icon(Icons.check_rounded, color: _blue, size: 18)
              : null,
            onTap: () {
              setState(() => _quality = q);
              widget.onQuality(q);
              Navigator.pop(context);
            },
          )),
        const SizedBox(height: 16),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.enabled;
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border)),
      child: Column(children: [

        // ── Now Playing ──────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16))),
          child: Row(children: [
            // pulse dot
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.nowPlaying != null
                    ? _cyan.withOpacity(_pulseAnim.value)
                    : _dimmed,
                  boxShadow: widget.nowPlaying != null ? [
                    BoxShadow(
                      color: _cyan.withOpacity(_pulseAnim.value * 0.5),
                      blurRadius: 6)
                  ] : []),
              )),
            const SizedBox(width: 8),
            Expanded(child: widget.nowPlaying != null
              ? _ScrollingTitle(title: widget.nowPlaying!)
              : const Text('Nothing playing', style: TextStyle(
                  fontSize: 12, color: Color(0xFF4B6070)))),
            const SizedBox(width: 8),
            // quality badge — tappable
            GestureDetector(
              onTap: e ? _showQualityPicker : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: e
                    ? _blue.withOpacity(0.15)
                    : _surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: e
                      ? _blue.withOpacity(0.4)
                      : _border)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_quality, style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: e ? _blue : _dimmed)),
                  const SizedBox(width: 3),
                  Icon(Icons.expand_more_rounded,
                    size: 12,
                    color: e ? _blue : _dimmed),
                ]),
              ),
            ),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(children: [

            // ── Row 1: Transport ────────────────────────
            Row(children: [
              _seekBtn(Icons.replay_10_rounded, _cyan,
                e ? widget.onSeekBack : null),
              const SizedBox(width: 8),
              Expanded(child: _playPauseBtn(e)),
              const SizedBox(width: 8),
              _seekBtn(Icons.forward_10_rounded, _cyan,
                e ? widget.onSeekForward : null),
            ]),

            const SizedBox(height: 10),

            // ── Row 2: Volume ────────────────────────────
            Row(children: [
              _volBtn(Icons.volume_down_rounded,
                e ? widget.onVolDown : null),
              const SizedBox(width: 8),
              Expanded(child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: _purple.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _purple.withOpacity(0.2))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  Container(
                    width: 80, height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(colors: [
                        _purple.withOpacity(0.3),
                        _purple,
                      ]))),
                ]),
              )),
              const SizedBox(width: 8),
              _volBtn(Icons.volume_up_rounded,
                e ? widget.onVolUp : null),
            ]),

            const SizedBox(height: 10),

            // ── Row 3: Actions ───────────────────────────
            Row(children: [
              Expanded(child: _actionBtn(
                Icons.stop_rounded, 'Stop', _red,
                e ? () {
                  setState(() { _playing = true; _muted = false; });
                  widget.onStop();
                } : null)),
              const SizedBox(width: 8),
              Expanded(child: _actionBtn(
                Icons.replay_rounded, 'Replay', _cyan,
                e ? widget.onReplay : null)),
              const SizedBox(width: 8),
              Expanded(child: _actionBtn(
                _muted
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
                _muted ? 'Unmute' : 'Mute',
                _amber,
                e ? () {
                  setState(() => _muted = !_muted);
                  _muted ? widget.onMute() : widget.onUnmute();
                } : null)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _playPauseBtn(bool e) => GestureDetector(
    onTap: e ? () {
      setState(() => _playing = !_playing);
      _playing ? widget.onResume() : widget.onPause();
    } : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52,
      decoration: BoxDecoration(
        gradient: e ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _playing
            ? [_blue.withOpacity(0.9), _cyan.withOpacity(0.7)]
            : [_blue, _cyan]) : null,
        color: e ? null : _surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: e ? [
          BoxShadow(
            color: _blue.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4))
        ] : []),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 26,
          color: e ? Colors.white : _dimmed),
        const SizedBox(width: 6),
        Text(
          _playing ? 'Pause' : 'Resume',
          style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700,
            color: e ? Colors.white : _dimmed)),
      ]),
    ),
  );

  Widget _seekBtn(IconData icon, Color color, VoidCallback? onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          color: onTap != null
            ? color.withOpacity(0.10)
            : _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: onTap != null
              ? color.withOpacity(0.3)
              : _border)),
        child: Icon(icon, size: 22,
          color: onTap != null ? color : _dimmed)),
    );

  Widget _volBtn(IconData icon, VoidCallback? onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: onTap != null
            ? _purple.withOpacity(0.10)
            : _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: onTap != null
              ? _purple.withOpacity(0.25)
              : _border)),
        child: Icon(icon, size: 18,
          color: onTap != null ? _purple : _dimmed)),
    );

  Widget _actionBtn(IconData icon, String label,
      Color color, VoidCallback? onTap) =>
    GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: onTap != null
            ? color.withOpacity(0.10)
            : _surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: onTap != null
              ? color.withOpacity(0.3)
              : _border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18,
            color: onTap != null ? color : _dimmed),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w600,
            color: onTap != null ? color : _dimmed)),
        ]),
      ),
    );
}

class _ScrollingTitle extends StatefulWidget {
  final String title;
  const _ScrollingTitle({required this.title});

  @override
  State<_ScrollingTitle> createState() => _ScrollingTitleState();
}

class _ScrollingTitleState extends State<_ScrollingTitle>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8));
    _anim = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(-1, 0),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.linear));
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: SlideTransition(
      position: _anim,
      child: Text(widget.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: Colors.white)),
    ),
  );
}
