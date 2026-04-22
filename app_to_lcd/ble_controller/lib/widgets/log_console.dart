import 'package:flutter/material.dart';

class LogConsole extends StatelessWidget {
  final List<String> logs;
  final VoidCallback onClear;
  const LogConsole({super.key, required this.logs, required this.onClear});

  Color _color(String msg) {
    if (msg.contains('[ERROR]') || msg.contains('failed')) return const Color(0xFFFF3D71);
    if (msg.contains('[SEND]'))   return const Color(0xFFFFAB00);
    if (msg.contains('[URL]'))    return const Color(0xFFFF0000);
    if (msg.contains('[BLE]'))    return const Color(0xFF00E676);
    if (msg.contains('[SCAN]'))   return const Color(0xFF00E5FF);
    if (msg.contains('[PLAYER]')) return const Color(0xFF7C4DFF);
    if (msg.contains('[APP]'))    return const Color(0xFF00E5FF);
    if (msg.contains('[NOTIFY]')) return const Color(0xFF7C4DFF);
    return const Color(0xFF4A5568);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Row(children: [
            const Icon(Icons.terminal, color: Color(0xFF4A5568), size: 16),
            const SizedBox(width: 8),
            const Text('EVENT LOG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: Color(0xFF4A5568), letterSpacing: 1.5)),
            const Spacer(),
            GestureDetector(
              onTap: onClear,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2A3A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('CLEAR', style: TextStyle(fontSize: 9,
                  fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
              ),
            ),
          ]),
        ),
        Container(height: 1, color: const Color(0xFF1E2A3A)),
        SizedBox(
          height: 200,
          child: logs.isEmpty
            ? Center(child: Text('No events yet',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.15))))
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: logs.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('> ', style: TextStyle(fontSize: 10,
                      color: _color(logs[i]), fontWeight: FontWeight.w700)),
                    Expanded(child: Text(logs[i], style: TextStyle(fontSize: 10,
                      color: _color(logs[i]).withOpacity(0.8), height: 1.4))),
                  ]),
                ),
              ),
        ),
      ]),
    );
  }
}
