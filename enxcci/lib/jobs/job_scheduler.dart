import 'dart:async';

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

  final Map<String, Timer> _timers = {};
  final Map<String, DateTime> _lastRunAt = {};
  final Set<String> _inFlight = {};
  bool _running = false;

  bool get isRunning => _running;

  void updateConnections(List<EnXcciConfig> value) {
    connections = value;
  }

  Future<void> start(List<EnXJob> jobs) async {
    await stop();
    _running = true;
    for (final job in jobs.where((j) => j.active)) {
      _schedule(job);
    }
    onLog?.call('INFO', '${_timers.length} jobs ativos iniciados');
  }

  void _schedule(EnXJob job) {
    // Cancela timer anterior se existir
    _timers[job.id]?.cancel();

    // Calcula quantos ms faltam para o próximo segundo 00
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year, now.month, now.day,
      now.hour, now.minute + 1, 0, 0, 0,
    );
    final delay = nextMinute.difference(now);

    // Aguarda até o segundo 00 e então dispara em loop pelo intervalSeconds
    _timers[job.id] = Timer(delay, () {
      _fireJob(job);
      // Após o primeiro disparo no segundo 00, repete pelo intervalo configurado
      _timers[job.id] = Timer.periodic(
        Duration(seconds: job.intervalSeconds),
        (_) => _fireJob(job),
      );
    });

    onJobUpdate?.call(job.copyWith(nextRun: nextMinute));
    onLog?.call('INFO', 'jobs iniciados');
  }

  void _fireJob(EnXJob job) {
    if (_inFlight.contains(job.id)) return;
    final now = DateTime.now();
    final lastRun = _lastRunAt[job.id];
    if (lastRun != null &&
        now.difference(lastRun).inSeconds < job.intervalSeconds) {
      return;
    }
    _lastRunAt[job.id] = now;
    _inFlight.add(job.id);
    _run(job).whenComplete(() => _inFlight.remove(job.id));
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
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _lastRunAt.clear();
    _inFlight.clear();
    _running = false;
  }

  Future<void> dispose() async => stop();
}