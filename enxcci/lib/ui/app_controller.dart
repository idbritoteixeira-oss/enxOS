import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/database/mysql_pool.dart';
import 'package:enxcci/dataniverse/dataniverse_client.dart';
import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/jobs/job_scheduler.dart';

class EnXLogEntry {
  EnXLogEntry(this.level, this.message, {DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  final String level;
  final String message;
  final DateTime timestamp;
}

class AppController extends ChangeNotifier {
  AppController._({
    required this.repository,
    required this.pool,
    required this.dataniverse,
    required this.engine,
    required this.scheduler,
  });

  final EnXcciRepository repository;
  final MysqlPool pool;
  final DataniverseClient dataniverse;
  final EnXcciEngine engine;
  final JobScheduler scheduler;

  final List<EnXLogEntry> logs = [];
  List<EnXcciConfig> connections = [];
  List<EnXJob> jobs = [];
  bool dataniverseOnline = false;
  bool initialized = false;
  Timer? _healthTimer;
  Timer? _dataniverseTimer;

  static Future<AppController> create() async {
    final preferences = await SharedPreferences.getInstance();
    late AppController controller;
    final repository = EnXcciRepository(preferences);
    final pool = MysqlPool();
    final dataniverse = DataniverseClient(
      password: 'enxcci-local',
      onLog: (message, {error = false}) {
        controller.addLog(error ? 'ERROR' : 'INFO', message);
      },
    );
    final engine = EnXcciEngine(
      dataniverse: dataniverse,
      onLog: (level, message) => controller.addLog(level, message),
    );
    final scheduler = JobScheduler(
      pool: pool,
      engine: engine,
      connections: const [],
      onLog: (level, message) => controller.addLog(level, message),
      onJobUpdate: (job) => controller._handleJobUpdate(job),
    );
    controller = AppController._(
      repository: repository,
      pool: pool,
      dataniverse: dataniverse,
      engine: engine,
      scheduler: scheduler,
    );
    await controller.initialize();
    return controller;
  }

  Future<void> initialize() async {
    connections = repository.loadConnections();
    jobs = repository.loadJobs();
    scheduler.updateConnections(connections);
    addLog('INFO', 'EnXcci iniciando');
    dataniverse.startRetryLoop();
    await refreshDataniverseStatus();
    await pool.connectActive(connections);
    await scheduler.start(jobs);
    _healthTimer = Timer.periodic(const Duration(seconds: 30), (_) => healthWatchdog());
    _dataniverseTimer = Timer.periodic(const Duration(seconds: 5), (_) => refreshDataniverseStatus());
    initialized = true;
    notifyListeners();
  }

  Future<void> refreshDataniverseStatus() async {
    dataniverseOnline = await dataniverse.isOnline();
    notifyListeners();
  }

  Future<void> healthWatchdog() async {
    await refreshDataniverseStatus();
    for (final config in connections.where((item) => item.active)) {
      final result = await pool.ping(config);
      addLog(
        result.online ? 'SUCCESS' : 'ERROR',
        '${config.label}: ${result.online ? '${result.latencyMs} ms' : 'offline'}',
      );
    }
  }

  Future<void> setAllJobsActive(bool active) async {
    jobs = jobs.map((job) => job.copyWith(active: active)).toList();
    await repository.saveJobs(jobs);
    await scheduler.start(jobs);
    addLog('INFO', active ? 'Todos os jobs iniciados' : 'Todos os jobs parados');
    notifyListeners();
  }

  Future<void> upsertConnection(EnXcciConfig config) async {
    final index = connections.indexWhere((item) => item.id == config.id);
    if (index == -1) {
      connections = [...connections, config];
    } else {
      connections = [...connections]..[index] = config;
    }
    await repository.saveConnections(connections);
    scheduler.updateConnections(connections);
    final result = await pool.ping(config);
    addLog(result.online ? 'SUCCESS' : 'ERROR', '${config.label}: ${result.online ? 'conectado' : 'falha de conexão'}');
    notifyListeners();
  }

  Future<void> removeConnection(EnXcciConfig config) async {
    await pool.close(config.id);
    connections = connections.where((item) => item.id != config.id).toList();
    await repository.saveConnections(connections);
    scheduler.updateConnections(connections);
    notifyListeners();
  }

  Future<MysqlPingResult> pingConnection(EnXcciConfig config) async {
    final result = await pool.ping(config);
    addLog(result.online ? 'SUCCESS' : 'ERROR', '${config.label}: ${result.online ? '${result.latencyMs} ms' : result.error ?? 'offline'}');
    notifyListeners();
    return result;
  }

  Future<void> upsertJob(EnXJob job) async {
    final index = jobs.indexWhere((item) => item.id == job.id);
    if (index == -1) {
      jobs = [...jobs, job];
    } else {
      jobs = [...jobs]..[index] = job;
    }
    await repository.saveJobs(jobs);
    await scheduler.start(jobs);
    notifyListeners();
  }

  void _handleJobUpdate(EnXJob updated) {
    final index = jobs.indexWhere((item) => item.id == updated.id);
    if (index == -1) return;
    jobs = [...jobs]..[index] = updated;
    repository.saveJobs(jobs);
    notifyListeners();
  }

  Future<void> removeJob(EnXJob job) async {
    jobs = jobs.where((item) => item.id != job.id).toList();
    await repository.saveJobs(jobs);
    await scheduler.start(jobs);
    notifyListeners();
  }

  Future<void> toggleJob(EnXJob job, bool active) =>
      upsertJob(job.copyWith(active: active));

  void addLog(String level, String message) {
    logs.add(EnXLogEntry(level, message));
    if (logs.length > 100) logs.removeRange(0, logs.length - 100);
    notifyListeners();
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _dataniverseTimer?.cancel();
    scheduler.dispose();
    pool.closeAll();
    dataniverse.dispose();
    super.dispose();
  }

  EnXcciConfig newConnection() => EnXcciConfig(
        id: const Uuid().v4(),
        label: 'MySQL ${connections.length + 1}',
        host: '127.0.0.1',
        port: 3306,
        user: '',
        password: '',
        database: '',
      );

  EnXJob newJob() => EnXJob(
        id: const Uuid().v4(),
        label: 'Job ${jobs.length + 1}',
        connectionId: connections.isEmpty ? '' : connections.first.id,
        query: 'SELECT 1',
        targetTable: 'ottschain',
        intervalSeconds: 60,
      );
}