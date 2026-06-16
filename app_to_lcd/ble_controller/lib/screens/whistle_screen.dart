import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/board_state.dart';

class WhistleScreen extends StatefulWidget {
  const WhistleScreen({super.key});
  @override
  State<WhistleScreen> createState() => _WhistleScreenState();
}

class _WhistleScreenState extends State<WhistleScreen> {
  static const _bg     = Color(0xFF000000);
  static const _card   = Color(0xFF0D1520);
  static const _border = Color(0xFF1E3048);
  static const _cyan   = Color(0xFF00E5FF);
  static const _green  = Color(0xFF34C759);
  static const _red    = Color(0xFFFF3D71);
  static const _amber  = Color(0xFFFF9F0A);
  static const _label  = Color(0xFF4A5568);

  static const _presets = [
    (count: 1, label: 'Eggs\nVegetables'),
    (count: 2, label: 'Rice\nDal'),
    (count: 3, label: 'Rajma\nChana'),
    (count: 4, label: 'Mutton\nChicken'),
    (count: 5, label: 'Hard\nLegumes'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble   = context.read<BleService>();
      final board = context.read<BoardState>();
      if (board.whistleTarget == 0 && ble.state == ConnState.connected) {
        ble.whistleSetTarget(3);
        board.whistleTarget = 3;
        board.notifyListeners();
      }
    });
  }

  void _setTarget(int n, BleService ble, BoardState board) {
    if (!mounted) return;
    ble.whistleSetTarget(n);
    board.whistleTarget = n;
    board.notifyListeners();
    setState(() {});
  }

  void _showCustomDialog(BleService ble, BoardState board) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1520),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Custom Target',
          style: TextStyle(color: Colors.white, fontSize: 16,
            fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white, fontSize: 24),
          decoration: InputDecoration(
            hintText: 'Enter number',
            hintStyle: const TextStyle(color: _label),
            filled: true,
            fillColor: const Color(0xFF080C14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _cyan))),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _label))),
          TextButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text.trim());
              if (n != null && n > 0) {
                _setTarget(n, ble, board);
                Navigator.pop(context);
              }
            },
            child: const Text('SET',
              style: TextStyle(color: _cyan, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ble       = context.watch<BleService>();
    final board     = context.watch<BoardState>();
    final connected = ble.state == ConnState.connected;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 17, color: _cyan),
          onPressed: () => Navigator.pop(context)),
        title: const Row(children: [
          Text('📣', style: TextStyle(fontSize: 18)),
          SizedBox(width: 8),
          Text('Whistle Counter', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(children: [

          // Status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: board.whistleActive
                ? _green.withOpacity(0.08)
                : _label.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: board.whistleActive
                  ? _green.withOpacity(0.3)
                  : _border)),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: board.whistleActive ? _green : _label,
                  boxShadow: board.whistleActive ? [
                    BoxShadow(color: _green.withOpacity(0.5), blurRadius: 6)
                  ] : [])),
              const SizedBox(width: 10),
              Text(
                board.whistleActive
                  ? 'Counting active — listening for whistles'
                  : 'Counting stopped',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: board.whistleActive ? _green : _label)),
            ]),
          ),

          const SizedBox(height: 24),

          // Count display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: board.whistleActive
                  ? _cyan.withOpacity(0.25)
                  : _border),
              boxShadow: board.whistleActive ? [
                BoxShadow(color: _cyan.withOpacity(0.06), blurRadius: 24)
              ] : []),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                Text(
                  '${board.whistleCount}',
                  style: TextStyle(
                    fontSize: 96,
                    fontWeight: FontWeight.w100,
                    color: board.whistleActive ? _cyan : Colors.white,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()])),
                if (board.whistleTarget > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(
                      ' / ${board.whistleTarget}',
                      style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.w200,
                        color: _label, height: 1))),
              ]),
              const SizedBox(height: 6),
              Text(
                board.whistleTarget > 0
                  ? '${board.whistleCount} of ${board.whistleTarget} whistle${board.whistleTarget == 1 ? '' : 's'}'
                  : board.whistleCount == 1 ? 'whistle' : 'whistles',
                style: const TextStyle(fontSize: 13, color: _label)),
              if (board.whistleTarget > 0) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (board.whistleCount / board.whistleTarget)
                        .clamp(0.0, 1.0),
                      backgroundColor: _border,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        board.whistleCount >= board.whistleTarget
                          ? _green : _cyan),
                      minHeight: 6))),
              ],
            ]),
          ),

          const SizedBox(height: 24),

          // Start / Stop
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: connected ? () {
                if (board.whistleActive) {
                  ble.whistleStop();
                  board.whistleActive = false;
                  board.whistleCount  = 0;
                  board.notifyListeners();
                } else {
                  ble.whistleStart();
                  board.whistleCount  = 0;
                  board.whistleActive = true;
                  board.notifyListeners();
                }
              } : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: connected
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: board.whistleActive
                          ? [_red.withOpacity(0.9), _red.withOpacity(0.6)]
                          : [_green.withOpacity(0.9), _green.withOpacity(0.6)])
                    : null,
                  color: connected ? null : _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: connected ? Colors.transparent : _border),
                  boxShadow: connected ? [
                    BoxShadow(
                      color: (board.whistleActive ? _red : _green)
                        .withOpacity(0.3),
                      blurRadius: 16, offset: const Offset(0, 4))
                  ] : []),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  Icon(
                    board.whistleActive
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                    size: 24,
                    color: connected ? Colors.white : _label),
                  const SizedBox(width: 8),
                  Text(
                    board.whistleActive ? 'STOP' : 'START',
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: connected ? Colors.white : _label)),
                ]),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Target section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: board.whistleTarget > 0
                  ? _cyan.withOpacity(0.25)
                  : _border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

              const Text('SET ALERT TARGET', style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700,
                color: _cyan, letterSpacing: 1.5)),

              const SizedBox(height: 4),
              const Text(
                'Alarm plays through speaker + phone notification when target is reached',
                style: TextStyle(fontSize: 11, color: _label)),

              const SizedBox(height: 14),

              // Preset grid — 5 presets + custom box
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.1,
                children: [
                  ..._presets.map((p) {
                    final selected = board.whistleTarget == p.count;
                    return GestureDetector(
                      onTap: connected
                        ? () => _setTarget(p.count, ble, board)
                        : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: selected
                            ? _cyan.withOpacity(0.12)
                            : const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                              ? _cyan.withOpacity(0.6)
                              : const Color(0xFF1E2A3A),
                            width: selected ? 1.5 : 1),
                          boxShadow: selected ? [
                            BoxShadow(
                              color: _cyan.withOpacity(0.15), blurRadius: 8)
                          ] : []),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Text('${p.count}',
                            style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w200,
                              color: selected ? _cyan : Colors.white,
                              height: 1)),
                          const SizedBox(height: 4),
                          Text(p.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              color: selected
                                ? _cyan.withOpacity(0.8)
                                : _label,
                              height: 1.3)),
                        ]),
                      ),
                    );
                  }),
                  // Custom box
                  GestureDetector(
                    onTap: connected
                      ? () => _showCustomDialog(ble, board)
                      : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: _presets.every(
                            (p) => board.whistleTarget != p.count) &&
                            board.whistleTarget > 0
                          ? _cyan.withOpacity(0.12)
                          : const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _presets.every(
                              (p) => board.whistleTarget != p.count) &&
                              board.whistleTarget > 0
                            ? _cyan.withOpacity(0.6)
                            : const Color(0xFF1E2A3A)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        Text(
                          _presets.every(
                              (p) => board.whistleTarget != p.count) &&
                              board.whistleTarget > 0
                            ? '${board.whistleTarget}'
                            : '+',
                          style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w200,
                            color: _presets.every(
                                (p) => board.whistleTarget != p.count) &&
                                board.whistleTarget > 0
                              ? _cyan : _label,
                            height: 1)),
                        const SizedBox(height: 4),
                        const Text('Custom',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9, color: _label, height: 1.3)),
                      ]),
                    ),
                  ),
                ],
              ),
            ]),
          ),

          if (!connected) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _red.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _red.withOpacity(0.2))),
              child: Row(children: [
                const Icon(Icons.bluetooth_disabled_rounded,
                  color: _red, size: 16),
                const SizedBox(width: 10),
                const Expanded(child: Text(
                  'Connect to BLE-Hub to control the counter',
                  style: TextStyle(fontSize: 12, color: _red))),
              ]),
            ),
          ],

        ]),
      ),
    );
  }
}
