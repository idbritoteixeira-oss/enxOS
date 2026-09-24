import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

typedef DataniverseLog = void Function(String message, {bool error});

class DataniverseClient {
  DataniverseClient({
    this.baseUrl = 'http://127.0.0.1:8081',
    required this.password,
    http.Client? client,
    this.onLog,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String password;
  final http.Client _client;
  final DataniverseLog? onLog;
  final List<Map<String, dynamic>> _retryQueue = [];
  Timer? _retryTimer;

  int get pendingCount => _retryQueue.length;

  Future<Map<String, dynamic>> command(Map<String, dynamic> body) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/command'),
        headers: {
          'Content-Type': 'application/json',
          'X-Password': password,
        },
        body: jsonEncode(body),
      );
      final decoded = _decode(response);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }
      throw StateError(decoded['message']?.toString() ?? 'Dataniverse rejeitou o comando');
    } catch (error) {
      _enqueue(body);
      onLog?.call('Dataniverse offline; comando enfileirado (${_retryQueue.length})', error: true);
      return {
        'status': 'QUEUED',
        'message': 'Dataniverse offline; comando será reenviado.',
        'data': body,
      };
    }
  }

  Future<bool> isOnline() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<void> enqueueBatch(List<Map<String, dynamic>> commands) async {
    for (final body in commands) {
      await command(body);
    }
  }

  void startRetryLoop() {
    _retryTimer ??= Timer.periodic(const Duration(seconds: 5), (_) => flushQueue());
  }

  Future<void> flushQueue() async {
    if (_retryQueue.isEmpty || !await isOnline()) return;
    final pending = List<Map<String, dynamic>>.from(_retryQueue);
    _retryQueue.clear();
    for (var index = 0; index < pending.length; index++) {
      final body = pending[index];
      try {
        final response = await _client.post(
          Uri.parse('$baseUrl/command'),
          headers: {
            'Content-Type': 'application/json',
            'X-Password': password,
          },
          body: jsonEncode(body),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw StateError('HTTP ${response.statusCode}');
        }
      } catch (_) {
        _retryQueue.add(body);
        _retryQueue.addAll(pending.skip(index + 1));
        onLog?.call('Retry interrompido; ${_retryQueue.length} comandos pendentes', error: true);
        break;
      }
    }
    if (_retryQueue.isEmpty) {
      onLog?.call('Fila do Dataniverse reenviada com sucesso');
    }
  }

  void _enqueue(Map<String, dynamic> body) {
    _retryQueue.add(body);
    startRetryLoop();
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};
  }

  void dispose() {
    _retryTimer?.cancel();
    _client.close();
  }
}