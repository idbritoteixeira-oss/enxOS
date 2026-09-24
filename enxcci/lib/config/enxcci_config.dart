import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class EnXcciConfig {
  const EnXcciConfig({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.database,
    this.active = true,
  });

  final String id;
  final String label;
  final String host;
  final int port;
  final String user;
  final String password;
  final String database;
  final bool active;

  EnXcciConfig copyWith({
    String? id,
    String? label,
    String? host,
    int? port,
    String? user,
    String? password,
    String? database,
    bool? active,
  }) {
    return EnXcciConfig(
      id: id ?? this.id,
      label: label ?? this.label,
      host: host ?? this.host,
      port: port ?? this.port,
      user: user ?? this.user,
      password: password ?? this.password,
      database: database ?? this.database,
      active: active ?? this.active,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'user': user,
        'password': password,
        'database': database,
        'active': active,
      };

  factory EnXcciConfig.fromJson(Map<String, dynamic> json) => EnXcciConfig(
        id: json['id'] as String? ?? const Uuid().v4(),
        label: json['label'] as String? ?? 'MySQL',
        host: json['host'] as String? ?? '127.0.0.1',
        port: (json['port'] as num?)?.toInt() ?? 3306,
        user: json['user'] as String? ?? '',
        password: json['password'] as String? ?? '',
        database: json['database'] as String? ?? '',
        active: json['active'] as bool? ?? true,
      );
}

class EnXJob {
  const EnXJob({
    required this.id,
    required this.label,
    required this.connectionId,
    required this.query,
    required this.targetTable,
    this.seedShard,
    required this.intervalSeconds,
    this.active = true,
    this.lastResult,
    this.lastRun,
    this.nextRun,
  });

  final String id;
  final String label;
  final String connectionId;
  final String query;
  final String targetTable;
  final String? seedShard;
  final int intervalSeconds;
  final bool active;
  final String? lastResult;
  final DateTime? lastRun;
  final DateTime? nextRun;

  EnXJob copyWith({
    String? id,
    String? label,
    String? connectionId,
    String? query,
    String? targetTable,
    String? seedShard,
    int? intervalSeconds,
    bool? active,
    String? lastResult,
    DateTime? lastRun,
    DateTime? nextRun,
  }) {
    return EnXJob(
      id: id ?? this.id,
      label: label ?? this.label,
      connectionId: connectionId ?? this.connectionId,
      query: query ?? this.query,
      targetTable: targetTable ?? this.targetTable,
      seedShard: seedShard ?? this.seedShard,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      active: active ?? this.active,
      lastResult: lastResult ?? this.lastResult,
      lastRun: lastRun ?? this.lastRun,
      nextRun: nextRun ?? this.nextRun,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'connectionId': connectionId,
        'query': query,
        'targetTable': targetTable,
        'seedShard': seedShard,
        'intervalSeconds': intervalSeconds,
        'active': active,
        'lastResult': lastResult,
        'lastRun': lastRun?.toIso8601String(),
        'nextRun': nextRun?.toIso8601String(),
      };

  factory EnXJob.fromJson(Map<String, dynamic> json) => EnXJob(
        id: json['id'] as String? ?? const Uuid().v4(),
        label: json['label'] as String? ?? 'Novo job',
        connectionId: json['connectionId'] as String? ?? '',
        query: json['query'] as String? ?? 'SELECT 1',
        targetTable: json['targetTable'] as String? ?? 'ottschain',
        seedShard: json['seedShard'] as String?,
        intervalSeconds: (json['intervalSeconds'] as num?)?.toInt() ?? 60,
        active: json['active'] as bool? ?? true,
        lastResult: json['lastResult'] as String?,
        lastRun: DateTime.tryParse(json['lastRun'] as String? ?? ''),
        nextRun: DateTime.tryParse(json['nextRun'] as String? ?? ''),
      );
}

class EnXcciRepository {
  EnXcciRepository(this.preferences);

  final SharedPreferences preferences;
  static const _connectionsKey = 'enxcci.connections';
  static const _jobsKey = 'enxcci.jobs';

  List<EnXcciConfig> loadConnections() {
    final raw = preferences.getStringList(_connectionsKey) ?? const [];
    return raw
        .map((item) => EnXcciConfig.fromJson(
              jsonDecode(item) as Map<String, dynamic>,
            ))
        .toList();
  }

  Future<void> saveConnections(List<EnXcciConfig> connections) {
    return preferences.setStringList(
      _connectionsKey,
      connections.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  List<EnXJob> loadJobs() {
    final raw = preferences.getStringList(_jobsKey) ?? const [];
    return raw
        .map((item) => EnXJob.fromJson(
              jsonDecode(item) as Map<String, dynamic>,
            ))
        .toList();
  }

  Future<void> saveJobs(List<EnXJob> jobs) {
    return preferences.setStringList(
      _jobsKey,
      jobs.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }
}