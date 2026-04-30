import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/board_event.dart';

class ScheduleScreen extends StatefulWidget {
  final List<ScheduleEntry> initialEntries;
  final bool enabled;
  final Function(List<ScheduleEntry>) onSave;

  const ScheduleScreen({
    super.key,
    required this.initialEntries,
    required this.enabled,
    required this.onSave,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with TickerProviderStateMixin {
  late List<ScheduleEntry> _entries;
  DateTime _selectedDate = DateTime.now();
  final _dateScrollCtrl  = ScrollController();
  final _urlCtrl         = TextEditingController();
  final _titleCtrl       = TextEditingController();
  bool _fetchingTitle    = false;
  bool _addingVideo      = false;
  bool _showAllEntries   = false;
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  late final List<DateTime> _dates;
  late final List<DateTime> _months;

  static const _bg      = Color(0xFF000000);
  static const _card    = Color(0xFF1C1C1E);
  static const _card2   = Color(0xFF2C2C2E);
  static const _border  = Color(0xFF3A3A3C);
  static const _amber   = Color(0xFFFF9F0A);
  static const _blue    = Color(0xFF0A84FF);
  static const _red     = Color(0xFFFF453A);
  static const _label   = Color(0xFF8E8E93);
  static const _white   = Colors.white;

  @override
  void initState() {
    super.initState();
    _entries = List.from(widget.initialEntries);
    final now = DateTime.now();
    _dates = List.generate(180, (i) =>
        DateTime(now.year, now.month, now.day + i));
    final seen = <String>{};
    _months = [];
    for (final d in _dates) {
      final key = '${d.year}-${d.month}';
      if (seen.add(key)) _months.add(DateTime(d.year, d.month, 1));
    }
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _dateScrollCtrl.addListener(() {
      final idx = (_dateScrollCtrl.offset / 56.0).round().clamp(0, _dates.length - 1);
      final d = _dates[idx];
      if (d.year != _selectedDate.year || d.month != _selectedDate.month) {
        // only update month highlight, not selected date
        if (mounted) setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _dateScrollCtrl.dispose();
    _urlCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _scrollToToday() {
    final idx = _dates.indexWhere((d) => _isSameDay(d, _selectedDate));
    if (idx >= 0) {
      _dateScrollCtrl.animateTo(
        idx * 56.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut);
    }
  }

  void _scrollToDate(DateTime date) {
    final idx = _dates.indexWhere((d) => _isSameDay(d, date));
    if (idx >= 0) {
      _dateScrollCtrl.animateTo(
        idx * 56.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut);
    }
  }

  void _selectDate(DateTime d) {
    setState(() { _selectedDate = d; _addingVideo = false; });
    _fadeCtrl.reset();
    _fadeCtrl.forward();
  }

  void _jumpToMonth(DateTime month) {
    final idx = _dates.indexWhere(
        (d) => d.year == month.year && d.month == month.month);
    if (idx < 0) return;
    _selectDate(_dates[idx]);
    _dateScrollCtrl.animateTo(
      idx * 56.0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  ScheduleEntry? _entryForDate(DateTime d) =>
      _entries.where((e) => _isSameDay(e.date, d)).firstOrNull;

  ScheduleEntry _getOrCreate(DateTime d) =>
      _entryForDate(d) ?? ScheduleEntry(date: d, playlist: []);

  void _upsert(ScheduleEntry e) {
    setState(() {
      _entries.removeWhere((x) => _isSameDay(x.date, e.date));
      if (e.playlist.isNotEmpty) _entries.add(e);
    });
  }

  void _deleteDay(DateTime d) =>
      setState(() => _entries.removeWhere((e) => _isSameDay(e.date, d)));

  Future<String> _fetchTitle(String videoId) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json');
      final req  = await client.getUrl(uri).timeout(const Duration(seconds: 5));
      final res  = await req.close().timeout(const Duration(seconds: 5));
      final body = await res.transform(utf8.decoder).join();
      client.close();
      return (jsonDecode(body) as Map<String, dynamic>)['title'] as String? ?? videoId;
    } catch (_) { return videoId; }
  }

  String? _extractId(String url) {
    for (final p in [
      RegExp(r'(?:v=)([A-Za-z0-9_-]{11})'),
      RegExp(r'(?:youtu\.be/)([A-Za-z0-9_-]{11})'),
      RegExp(r'(?:shorts/)([A-Za-z0-9_-]{11})'),
    ]) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1);
    }
    return null;
  }

  Future<void> _addVideo() async {
    final url    = _urlCtrl.text.trim();
    final manual = _titleCtrl.text.trim();
    if (url.isEmpty) return;
    final id = _extractId(url);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not a valid YouTube URL')));
      return;
    }
    String title = manual;
    if (title.isEmpty) {
      setState(() => _fetchingTitle = true);
      title = await _fetchTitle(id);
      if (mounted) setState(() => _fetchingTitle = false);
    }
    final entry = _getOrCreate(_selectedDate);
    _upsert(ScheduleEntry(
      date:     entry.date,
      playlist: [...entry.playlist,
        QueueItem(videoId: id, title: title, url: url)],
    ));
    _urlCtrl.clear(); _titleCtrl.clear();
    if (mounted) setState(() => _addingVideo = false);
  }

  DateTime get _visibleMonth {
    if (!_dateScrollCtrl.hasClients) return _selectedDate;
    final idx = (_dateScrollCtrl.offset / 56.0).round().clamp(0, _dates.length - 1);
    return _dates[idx];
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entryForDate(_selectedDate);
    final mnFull  = ['January','February','March','April','May','June',
                     'July','August','September','October','November','December'];
    final mnShort = ['Jan','Feb','Mar','Apr','May','Jun',
                     'Jul','Aug','Sep','Oct','Nov','Dec'];
    final dayShort = ['S','M','T','W','T','F','S'];
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
            size: 17, color: _blue),
          onPressed: () => Navigator.pop(context)),
        title: const Text('Schedule', style: TextStyle(
          color: _white, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () { widget.onSave(_entries); Navigator.pop(context); },
              child: Text('Save', style: TextStyle(
                fontSize: 17, color: _blue, fontWeight: FontWeight.w400)),
            ),
          ),
        ],
      ),

      body: Column(children: [

        // ── month strip ─────────────────────────────────────
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _months.length,
            itemBuilder: (_, i) {
              final m        = _months[i];
              final vm = _visibleMonth;
              final isActive = vm.year == m.year && vm.month == m.month;
              final hasDots  = _entries.any(
                  (e) => e.date.year == m.year && e.date.month == m.month);
              return GestureDetector(
                onTap: () => _jumpToMonth(m),
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isActive ? _amber : Colors.transparent,
                    borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(mnFull[m.month - 1], style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: isActive ? Colors.black : _label)),
                    if (hasDots && !isActive) ...[
                      const SizedBox(width: 4),
                      Container(width: 5, height: 5,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: _amber)),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),

        // ── date strip — Apple style ─────────────────────────
        SizedBox(
          height: 88,
          child: ListView.builder(
            controller: _dateScrollCtrl,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            itemCount: _dates.length,
            itemBuilder: (_, i) {
              final d          = _dates[i];
              final isSelected = _isSameDay(d, _selectedDate);
              final hasEntry   = _entryForDate(d) != null;
              final isToday    = _isSameDay(d, now);

              final isFirstOfMonth = i == 0 || _dates[i-1].month != d.month;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                if (isFirstOfMonth && i != 0)
                  Container(
                    width: 1, height: 50,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: const Color(0xFF3A3A3C)),
                GestureDetector(
                onTap: () => _selectDate(d),
                child: Container(
                  width: 48,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // day letter
                      Text(dayShort[d.weekday % 7], style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500,
                        color: isSelected ? _amber : _label)),
                      const SizedBox(height: 6),
                      // date circle
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                            ? _amber
                            : isToday
                              ? _card
                              : Colors.transparent,
                          border: isToday && !isSelected
                            ? Border.all(color: _amber, width: 1.5)
                            : null),
                        child: Center(
                          child: Text('${d.day}', style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected || isToday
                              ? FontWeight.w700 : FontWeight.w400,
                            color: isSelected
                              ? Colors.black
                              : isToday
                                ? _amber
                                : _white))),
                      ),
                      const SizedBox(height: 4),
                      // dot
                      Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasEntry
                            ? (isSelected ? Colors.black54 : _amber)
                            : Colors.transparent)),
                    ],
                  ),
                ),
              )]);
            },
          ),
        ),

        // divider
        Container(height: 0.5, color: _border),

        // ── content ─────────────────────────────────────────
        Expanded(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                // heading
                Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(
                      _isSameDay(_selectedDate, now) ? 'Today'
                        : _isSameDay(_selectedDate,
                            now.add(const Duration(days: 1))) ? 'Tomorrow'
                        : '${mnFull[_selectedDate.month-1]} ${_selectedDate.day}',
                      style: const TextStyle(fontSize: 28,
                        fontWeight: FontWeight.w700, color: _white,
                        letterSpacing: -0.5)),
                    Text(
                      entry != null
                        ? '${entry.playlist.length} video${entry.playlist.length == 1 ? '' : 's'}'
                        : 'No videos scheduled',
                      style: const TextStyle(fontSize: 13, color: _label)),
                  ])),
                  if (entry != null)
                    TextButton(
                      onPressed: () => _deleteDay(_selectedDate),
                      style: TextButton.styleFrom(
                        foregroundColor: _red,
                        padding: EdgeInsets.zero),
                      child: const Text('Clear', style: TextStyle(
                        fontSize: 15, color: _red))),
                ]),

                const SizedBox(height: 16),

                // videos
                if (entry != null && entry.playlist.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(12)),
                    child: Column(children: [
                      ...entry.playlist.asMap().entries.map((e) =>
                        _videoRow(e.value, e.key, entry,
                          isLast: e.key == entry.playlist.length - 1)),
                    ]),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(12)),
                    child: Column(children: [
                      Icon(Icons.video_library_outlined,
                        color: _label.withOpacity(0.3), size: 32),
                      const SizedBox(height: 8),
                      const Text('No videos scheduled',
                        style: TextStyle(fontSize: 15, color: _label)),
                    ]),
                  ),

                const SizedBox(height: 16),

                // add button / form
                if (_addingVideo)
                  _addForm()
                else
                  GestureDetector(
                    onTap: () => setState(() => _addingVideo = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle,
                            color: _blue, size: 20),
                          const SizedBox(width: 8),
                          Text('Add Video', style: TextStyle(
                            fontSize: 15, color: _blue,
                            fontWeight: FontWeight.w400)),
                        ]),
                    ),
                  ),

                // all dates
                if (_entries.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: () =>
                      setState(() => _showAllEntries = !_showAllEntries),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(children: [
                        const Text('Scheduled Dates', style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700,
                          color: _white)),
                        const Spacer(),
                        Text(_showAllEntries ? 'Hide' : 'Show all',
                          style: const TextStyle(
                            fontSize: 15, color: _blue)),
                      ]),
                    ),
                  ),
                  if (_showAllEntries) ...[
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(12)),
                      child: Column(children: [
                        ...(List<ScheduleEntry>.from(_entries)
                          ..sort((a, b) => a.date.compareTo(b.date)))
                          .asMap().entries.map((e) =>
                            _entryRow(e.value, mnShort, mnFull,
                              isLast: e.key == _entries.length - 1)),
                      ]),
                    ),
                  ],
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _videoRow(QueueItem item, int idx, ScheduleEntry entry,
      {bool isLast = false}) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Text('${idx+1}', style: const TextStyle(
            fontSize: 15, color: _label, fontWeight: FontWeight.w400)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(item.title.isNotEmpty ? item.title : item.videoId,
              style: const TextStyle(
                fontSize: 15, color: _white, fontWeight: FontWeight.w400),
              overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              final updated = List<QueueItem>.from(entry.playlist)
                ..removeAt(idx);
              _upsert(ScheduleEntry(date: entry.date, playlist: updated));
            },
            child: const Icon(Icons.remove_circle_outline,
              color: _red, size: 22)),
        ]),
      ),
      if (!isLast)
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Container(height: 0.5, color: _border)),
    ]);
  }

  Widget _addForm() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      _field(_urlCtrl, 'YouTube URL', autofocus: true),
      const SizedBox(height: 1),
      _field(_titleCtrl, 'Title  (leave blank to auto-fetch)'),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => setState(() {
            _addingVideo = false;
            _urlCtrl.clear(); _titleCtrl.clear(); }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _card2,
              borderRadius: BorderRadius.circular(10)),
            child: const Text('Cancel', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: _label))))),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: GestureDetector(
          onTap: _fetchingTitle ? null : _addVideo,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.circular(10)),
            child: _fetchingTitle
              ? const Center(child: SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2,
                    color: Colors.white)))
              : const Text('Add', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.white,
                    fontWeight: FontWeight.w600))))),
      ]),
    ]),
  );

  Widget _entryRow(ScheduleEntry e, List<String> mnShort,
      List<String> mnFull, {bool isLast = false}) {
    final isSelected = _isSameDay(e.date, _selectedDate);
    final isToday    = _isSameDay(e.date, DateTime.now());
    return GestureDetector(
      onTap: () {
        _selectDate(e.date);
        _scrollToDate(e.date);
      },
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 12),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday ? _amber : _card2),
              child: Center(child: Text('${e.date.day}',
                style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: isToday ? Colors.black : _white)))),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(
                isToday ? 'Today'
                  : '${mnFull[e.date.month-1]} ${e.date.day}, ${e.date.year}',
                style: TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? _amber : _white)),
              Text('${e.playlist.length} video${e.playlist.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 13, color: _label)),
            ])),
            const Icon(Icons.chevron_right, color: _label, size: 20),
          ]),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 68),
            child: Container(height: 0.5, color: _border)),
      ]),
    );
  }

  Widget _field(TextEditingController ctrl, String hint,
      {bool autofocus = false}) =>
    Container(
      decoration: BoxDecoration(
        color: _card2,
        borderRadius: BorderRadius.circular(10)),
      child: TextField(
        controller: ctrl,
        autofocus: autofocus,
        style: const TextStyle(fontSize: 15, color: _white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 15, color: _label),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12))));
}
