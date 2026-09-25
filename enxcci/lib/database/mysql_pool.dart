import 'dart:isolate';

import 'package:mysql_client/mysql_client.dart';

import 'package:enxcci/config/enxcci_config.dart';

class MysqlPingResult {
  const MysqlPingResult({
    required this.online,
    required this.latencyMs,
    this.error,
  });

  final bool online;
  final int? latencyMs;
  final String? error;
}

class MysqlPool {
  final Map<String, MySQLConnection> _connections = {};

  Future<void> connectActive(List<EnXcciConfig> configs) async {
    for (final config in configs.where((item) => item.active)) {
      try {
        await _open(config);
      } catch (_) {
        // O watchdog registra a falha sem impedir os demais bancos de subir.
      }
    }
  }

  Future<MySQLConnection> _open(EnXcciConfig config) async {
    final existing = _connections[config.id];
    if (existing != null) return existing;

    final connection = await MySQLConnection.createConnection(
      host: config.host,
      port: config.port,
      userName: config.user,
      password: config.password,
      databaseName: config.database,
      secure: false, // <-- Desativa a exigência de SSL
    );
    await connection.connect();
    _connections[config.id] = connection;
    return connection;
  }

  Future<MysqlPingResult> ping(EnXcciConfig config) async {
    final stopwatch = Stopwatch()..start();
    try {
      final connection = await _open(config);
      await connection.execute('SELECT 1');
      stopwatch.stop();
      return MysqlPingResult(online: true, latencyMs: stopwatch.elapsedMilliseconds);
    } catch (error) {
      stopwatch.stop();
      _connections.remove(config.id);
      return MysqlPingResult(
        online: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: error.toString(),
      );
    }
  }

  Future<List<Map<String, dynamic>>> query(
    EnXcciConfig config,
    String sql,
  ) async {
    final connection = await _open(config);
    final result = await connection.execute(sql);
    return result.rows
        .map((row) => Map<String, dynamic>.from(row.assoc()))
        .toList();
  }

  Future<List<Map<String, dynamic>>> queryInIsolate(
    EnXcciConfig config,
    String sql,
  ) {
    return Isolate.run(() async {
      final connection = await MySQLConnection.createConnection(
        host: config.host,
        port: config.port,
        userName: config.user,
        password: config.password,
        databaseName: config.database,
        secure: false, // <-- Desativa a exigência de SSL no Isolate também
      );
      try {
        await connection.connect();
        final result = await connection.execute(sql);
        return result.rows
            .map((row) => Map<String, dynamic>.from(row.assoc()))
            .toList();
      } finally {
        await connection.close();
      }
    });
  }

  Future<void> close(String connectionId) async {
    final connection = _connections.remove(connectionId);
    await connection?.close();
  }

  Future<void> closeAll() async {
    final connections = _connections.values.toList();
    _connections.clear();
    for (final connection in connections) {
      await connection.close();
    }
  }
}
