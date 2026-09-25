import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'package:enxcci/config/enxcci_config.dart';

class EnXApiPingResult {
  const EnXApiPingResult({
    required this.online,
    required this.latencyMs,
    this.error,
  });

  final bool online;
  final int? latencyMs;
  final String? error;
}

class EnXApiProvider {
  EnXApiProvider({
    required this.config,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final EnXcciConfig config;
  final http.Client _client;

  Future<EnXApiPingResult> ping() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .get(_uri('/health'), headers: _headers())
          .timeout(const Duration(seconds: 4));
      stopwatch.stop();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return EnXApiPingResult(
          online: true,
          latencyMs: stopwatch.elapsedMilliseconds,
        );
      }
      return EnXApiPingResult(
        online: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: 'HTTP ${response.statusCode}',
      );
    } catch (error) {
      stopwatch.stop();
      return EnXApiPingResult(
        online: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: error.toString(),
      );
    }
  }

  Future<List<Map<String, dynamic>>> query(String sql) {
    return _query(
      baseUrl: config.gatewayUrl,
      token: config.token,
      profile: config.profile,
      sql: sql,
    );
  }

  Future<List<Map<String, dynamic>>> queryInIsolate(String sql) {
    return queryConfigInIsolate(config, sql);
  }

  static Future<List<Map<String, dynamic>>> queryConfigInIsolate(
    EnXcciConfig config,
    String sql,
  ) {
    return Isolate.run(() => _query(
          baseUrl: config.gatewayUrl,
          token: config.token,
          profile: config.profile,
          sql: sql,
        ));
  }

  static Future<List<Map<String, dynamic>>> _query({
    required String baseUrl,
    required String token,
    required String profile,
    required String sql,
  }) async {
    final response = await http
        .post(
          _buildUri(baseUrl, '/query'),
          headers: {
            'Content-Type': 'application/json',
            'X-EnX-Token': token,
          },
          body: jsonEncode({
            'query': sql,
            'profile': profile,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final decoded = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(decoded['message']?.toString() ?? 'Gateway rejeitou a consulta');
    }
    final rows = decoded['data'];
    if (rows is! List) {
      throw StateError('Gateway retornou um payload de dados inválido');
    }
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Map<String, String> _headers() => {
        'Accept': 'application/json',
        'X-EnX-Token': config.token,
      };

  Uri _uri(String path) => _buildUri(config.gatewayUrl, path);

  static Uri _buildUri(String baseUrl, String path) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalized$path');
  }

  static Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};
  }

  void dispose() => _client.close();
}