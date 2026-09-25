import 'package:flutter/material.dart';

import 'package:enxcci/ui/app_controller.dart';
import 'package:enxcci/ui/connections_screen.dart';
import 'package:enxcci/ui/jobs_screen.dart';
import 'package:enxcci/ui/log_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final screens = [
      _Dashboard(controller: controller),
      ConnectionsScreen(controller: controller),
      JobsScreen(controller: controller),
      LogScreen(controller: controller),
    ];
    return Scaffold(
      body: SafeArea(child: screens[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Visão geral'),
          NavigationDestination(icon: Icon(Icons.storage_outlined), selectedIcon: Icon(Icons.storage), label: 'Conexões'),
          NavigationDestination(icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule), label: 'Jobs'),
          NavigationDestination(icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: 'Log'),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
        children: [
          Text('EnXcci', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('enxOS data engine', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white60)),
          const SizedBox(height: 24),
          _StatusCard(online: controller.dataniverseOnline, pending: controller.dataniverse.pendingCount),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _MetricCard(label: 'Conexões', value: '${controller.connections.length}', color: const Color(0xFFFFB84D), icon: Icons.storage)),
              const SizedBox(width: 12),
              Expanded(child: _MetricCard(label: 'Jobs ativos', value: '${controller.jobs.where((job) => job.active).length}', color: const Color(0xFF41D5C3), icon: Icons.bolt)),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => controller.setAllJobsActive(controller.jobs.any((job) => !job.active)),
            icon: Icon(controller.jobs.any((job) => !job.active) ? Icons.play_arrow : Icons.stop),
            label: Text(controller.jobs.any((job) => !job.active) ? 'Iniciar todos os jobs' : 'Parar todos os jobs'),
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Atividade recente', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text('${controller.logs.length}/100', style: const TextStyle(color: Colors.white54)),
            ],
          ),
          const SizedBox(height: 10),
          if (controller.logs.isEmpty)
            const _EmptyPanel(message: 'Aguardando eventos do motor')
          else
            ...controller.logs.reversed.take(8).map((entry) => _LogRow(entry: entry)),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.online, required this.pending});

  final bool online;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final color = online ? const Color(0xFF41D5C3) : const Color(0xFFFFB84D);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withValues(alpha: .18), const Color(0xFF171B2A)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .36)),
      ),
      child: Row(
        children: [
          Icon(online ? Icons.cloud_done : Icons.cloud_off, color: color, size: 32),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dataniverse', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(online ? 'Online · Dataniverse HTTP 8080' : 'Offline · comandos em fila', style: TextStyle(color: color)),
          ])),
          if (pending > 0) Chip(label: Text('$pending pendentes'), avatar: const Icon(Icons.sync, size: 16)),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.color, required this.icon});

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF171B2A), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(height: 16),
          Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Colors.white60)),
        ]),
      );
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final EnXLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.level == 'ERROR' ? const Color(0xFFFF6B7A) : entry.level == 'SUCCESS' ? const Color(0xFF41D5C3) : Colors.white60;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Text(entry.level, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(width: 10),
        Expanded(child: Text(entry.message, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: const Color(0xFF171B2A), borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text(message, style: const TextStyle(color: Colors.white54))),
      );
}