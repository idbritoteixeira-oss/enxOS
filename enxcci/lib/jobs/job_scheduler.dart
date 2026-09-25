import 'dart:async';

import 'package:cron/cron.dart';

import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/database/mysql_pool.dart';
import 'package:enxcci/engine/enxcci_engine.dart';

typedef SchedulerLog = void Function(String level, String message);
typedef JobUpdate = void Function(EnXJob job);

class JobScheduler {
  JobScheduler({
    required this.pool,
    required this.engine,
    required this.connections,
    this.onLog,
    this.onJobUpdate,
  });

  final MysqlPool pool;
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
    for (final job in jobs.where((item) => item.active)) {
      _schedule(job);
    }
    onLog?.call('INFO', '${_scheduled.length} jobs ativos iniciados');
  }

  void _schedule(EnXJob job) {
    _cron.schedule(
      Schedule.parse('* * * * * *'),
      () async {
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
      },
    );
    _scheduled.add(job.id);
    onJobUpdate?.call(job.copyWith(
      nextRun: DateTime.now().add(Duration(seconds: job.intervalSeconds)),
    ));
  }

  Future<void> _run(EnXJob job) async {
    final config = connections.cast<EnXcciConfig?>().firstWhere(
          (item) => item?.id == job.connectionId,
          orElse: () => null,
        );
    if (config == null) {
      onLog?.call('ERROR', '${job.label}: conexão não encontrada');
      onJobUpdate?.call(job.copyWith(
        lastResult: 'Erro: conexão não encontrada',
        lastRun: DateTime.now(),
        nextRun: DateTime.now().add(Duration(seconds: job.intervalSeconds)),
      ));
      return;
    }
    try {
      onLog?.call('INFO', '${job.label}: executando consulta');
      final rows = await pool.queryInIsolate(config, job.query);
      final count = await engine.processRows(job: job, rows: rows);
      onJobUpdate?.call(job.copyWith(
        lastResult: '$count registros processados',
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
    await _cron.close();
  }
}