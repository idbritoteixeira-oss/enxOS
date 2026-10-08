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
      _scheduleNextRun(job);
    }
    onLog?.call('INFO', '${_timers.length} active jobs started');
  }

  void _scheduleNextRun(EnXJob job) {
    _timers[job.id]?.cancel();

    final now = DateTime.now();
    final secondsPassedInHour = now.minute * 60 + now.second;
    final nextIntervalSeconds =
        ((secondsPassedInHour ~/ job.intervalSeconds) + 1) *
            job.intervalSeconds;

    final nextRun = DateTime(
      now.year, now.month, now.day,
      now.hour, 0, 0, 0, 0,
    ).add(Duration(seconds: nextIntervalSeconds));

    final delay = nextRun.difference(now);

    _timers[job.id] = Timer(delay, () {
      _fireJob(job);
      _scheduleNextRun(job);
    });

    onJobUpdate?.call(job.copyWith(nextRun: nextRun));
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
      onLog?.call('ERROR', '${job.label}: script "${job.scriptId}" not registered');
      onJobUpdate?.call(job.copyWith(
        lastResult: 'Error: script not found',
        lastRun: DateTime.now(),
        nextRun: DateTime.now().add(Duration(seconds: job.intervalSeconds)),
      ));
      return;
    }
    final pool = {for (final c in connections) c.id: c};
    try {
      onLog?.call('INFO', '${job.label}: running script "${script.label}"');
      await script.run(
        connections: pool,
        dataniverse: engine.dataniverse,
        engine: engine,
        log: onLog ?? (_, __) {},
      );
      onJobUpdate?.call(job.copyWith(
        lastResult: 'Script executed successfully',
        lastRun: DateTime.now(),
        nextRun: DateTime.now().add(Duration(seconds: job.intervalSeconds)),
      ));
    } catch (error) {
      onLog?.call('ERROR', '${job.label}: $error');
      onJobUpdate?.call(job.copyWith(
        lastResult: 'Error: $error',
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