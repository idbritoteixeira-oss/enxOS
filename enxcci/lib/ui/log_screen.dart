import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:enxcci/ui/app_controller.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  String _filter = 'ALL';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final logs = widget.controller.logs.where((entry) => _filter == 'ALL' || entry.level == _filter).toList().reversed;
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: const Text('Log do motor'),
              actions: [
                PopupMenuButton<String>(
                  initialValue: _filter,
                  onSelected: (value) => setState(() => _filter = value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'ALL', child: Text('Todos')),
                    PopupMenuItem(value: 'INFO', child: Text('INFO')),
                    PopupMenuItem(value: 'SUCCESS', child: Text('SUCCESS')),
                    PopupMenuItem(value: 'ERROR', child: Text('ERROR')),
                  ],
                ),
                IconButton(onPressed: () => _copyLog(widget.controller.logs), icon: const Icon(Icons.copy_all)),
              ],
            ),
            body: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final entry = logs.elementAt(index);
                final color = entry.level == 'ERROR' ? const Color(0xFFFF6B7A) : entry.level == 'SUCCESS' ? const Color(0xFF41D5C3) : Colors.white70;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: SelectableText(
                    '${DateFormat('yyyy-MM-ddTHH:mm:ss').format(entry.timestamp)}  ${entry.level.padRight(7)} ${entry.message}',
                    style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 12),
                  ),
                );
              },
            ),
          );
        },
      );

  Future<void> _copyLog(List<EnXLogEntry> logs) async {
    final content = logs.map((entry) => '${entry.timestamp.toIso8601String()} ${entry.level} ${entry.message}').join('\n');
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Log copiado para a área de transferência')));
  }
}