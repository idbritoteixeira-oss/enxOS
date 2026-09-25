import 'dart:async';

import 'package:cron/cron.dart';

import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/jobs/script_registry.dart';

typedef SchedulerLog = void Function(String level, String message);
typedef JobUpdate = void Function(EnXJob job);

class JobScheduler {
  JobScheduler({
    required this.engine,
    required this.connections,
    this.onLog,
    this.onJobUpdate,
  });

  final EnXcciEngine engine;
  List<EnXcciConfig> connections;
  final SchedulerLog? onLog;
  final JobUpdate? onJobUpdate;
  Cron _cron = Cron();
  final Set<String> _scheduled = {};
  final Map<String, DateTime> _lastRunAt = {};
  final Set<String> _inFlight = {};
  bool _running = false;

  bool get isRunning => _running;

  void updateConnections(List<EnXcciConfig> value) {
    connections = value;
  }

  Future<void> start(List<EnXJob> jobs) async {
    await stop();
    _cron = Cron();
    _running = true;
    for (final job in jobs.where((j) => j.active)) {
      _schedule(job);
    }
    onLog?.call('INFO', '${_scheduled.length} jobs ativos iniciados');
  }

  void _schedule(EnXJob job) {
    _cron.schedule(Schedule.parse('* * * * * *'), () async {
      if (_inFlight.contains(job.id)) return;
      final now = DateTime.now();
      final lastRun = _lastRunAt[job.id];
      if (lastRun != null &&
    now.difference(lastRun).inSeconds < job.intervalSeconds) {
  return;
      }
      _lastRunAt[job.id] = now;
      _inFlight.add(job.id);
      try {
        await _run(job);
      } finally {
        _inFlight.remove(job.id);
      }
    });
    _scheduled.add(job.id);
    onJobUpdate?.call(job.copyWith(
      nextRun: DateTime.now().add(Duration(seconds: job.intervalSeconds)),
    ));
  }

  Future<void> _run(EnXJob job) async {
    final script = ScriptRegistry.get(job.scriptId);
    if (script == null) {
      onLog?.call('ERROR', '${job.label}: script "${job.scriptId}" não registrado');
      onJobUpdate?.call(job.copyWith(
        lastResult: 'Erro: script não encontrado',
        lastRun: DateTime.now(),
        nextRun: DateTime.now().add(Duration(seconds: job.intervalSeconds)),
      ));
      return;
    }
    final pool = {for (final c in connections) c.id: c};
    try {
      onLog?.call('INFO', '${job.label}: executando script "${script.label}"');
      await script.run(
        connections: pool,
        dataniverse: engine.dataniverse,
        engine: engine,
        log: onLog ?? (_, __) {},
      );
      onJobUpdate?.call(job.copyWith(
        lastResult: 'Script executado com sucesso',
        lastRun: DateTime.now(),
        nextRun: DateTime.now().add(Duration(seconds: job.intervalSeconds)),
      ));
    } catch (error) {
      onLog?.call('ERROR', '${job.label}: $error');
      onJobUpdate?.call(job.copyWith(
        lastResult: 'Erro: $error',
        lastRun: DateTime.now(),
        nextRun: DateTime.now().add(Duration(seconds: job.intervalSeconds)),
      ));
    }
  }

  Future<void> runNow(EnXJob job) => _run(job);

  Future<void> stop() async {
    await _cron.close();
    _scheduled.clear();
    _lastRunAt.clear();
    _inFlight.clear();
    _running = false;
  }

  Future<void> dispose() async {
    await stop();
  }
}