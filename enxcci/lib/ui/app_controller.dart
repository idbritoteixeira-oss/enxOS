import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/database/enx_api_provider.dart';
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
    required this.dataniverse,
    required this.engine,
    required this.scheduler,
  });

  final EnXcciRepository repository;
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
    final dataniverse = DataniverseClient(
      baseUrl: 'http://127.0.0.1:8080',
      password: const String.fromEnvironment(
        'DATANIVERSE_PASSWORD',
        defaultValue: 'enxcci-local',
      ),
      onLog: (message, {error = false}) {
        controller.addLog(error ? 'ERROR' : 'INFO', message);
      },
    );
    final engine = EnXcciEngine(
      dataniverse: dataniverse,
      onLog: (level, message) => controller.addLog(level, message),
    );
    final scheduler = JobScheduler(
      engine: engine,
      connections: const [],
      onLog: (level, message) => controller.addLog(level, message),
      onJobUpdate: (job) => controller._handleJobUpdate(job),
    );
    controller = AppController._(
      repository: repository,
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
      final result = await _pingGateway(config);
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
    addLog('INFO', active ? 'jobs iniciados' : 'jobs parados');
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
    final result = await _pingGateway(config);
    addLog(result.online ? 'SUCCESS' : 'ERROR', '${config.label}: ${result.online ? 'conectado' : 'falha de conexão'}');
    notifyListeners();
  }

  Future<void> removeConnection(EnXcciConfig config) async {
    connections = connections.where((item) => item.id != config.id).toList();
    await repository.saveConnections(connections);
    scheduler.updateConnections(connections);
    notifyListeners();
  }

  Future<EnXApiPingResult> pingConnection(EnXcciConfig config) async {
    final result = await _pingGateway(config);
    addLog(result.online ? 'SUCCESS' : 'ERROR', '${config.label}: ${result.online ? '${result.latencyMs} ms' : result.error ?? 'offline'}');
    notifyListeners();
    return result;
  }

  Future<EnXApiPingResult> _pingGateway(EnXcciConfig config) async {
    final provider = EnXApiProvider(config: config);
    try {
      return await provider.ping();
    } finally {
      provider.dispose();
    }
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
    dataniverse.dispose();
    super.dispose();
  }

  EnXcciConfig newConnection() => EnXcciConfig(
        id: const Uuid().v4(),
        label: 'Gateway ${connections.length + 1}',
        gatewayUrl: 'http://127.0.0.1:8099',
        token: '',
        profile: 'default',
      );
  EnXJob newJob() => EnXJob(
    id: const Uuid().v4(),
    label: 'Job ${jobs.length + 1}',
    scriptId: '',
    targetTable: '',
    intervalSeconds: 60,
  );
}