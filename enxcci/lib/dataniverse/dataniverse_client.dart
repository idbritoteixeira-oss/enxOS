import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum DataniverseTransport { http, tcp }

typedef DataniverseLog = void Function(String message, {bool error});

class DataniverseClient {
  DataniverseClient({
    this.baseUrl = 'http://127.0.0.1:8080',
    required this.password,
    this.transport = DataniverseTransport.http,
    this.tcpHost = '127.0.0.1',
    this.tcpPort = 8081,
    http.Client? client,
    this.onLog,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String password;
  final DataniverseTransport transport;
  final String tcpHost;
  final int tcpPort;
  final http.Client _client;
  final DataniverseLog? onLog;
  final List<Map<String, dynamic>> _retryQueue = [];
  Timer? _retryTimer;

  int get pendingCount => _retryQueue.length;

  Future<Map<String, dynamic>> command(Map<String, dynamic> body) async {
    try {
      return await _send(body);
    } catch (error) {
      _enqueue(body);
      onLog?.call(
        'Dataniverse offline; comando enfileirado (${_retryQueue.length})',
        error: true,
      );
      return {
        'status': 'QUEUED',
        'message': 'Dataniverse offline; comando será reenviado.',
        'data': body,
      };
    }
  }

  Future<bool> isOnline() async {
    try {
      if (transport == DataniverseTransport.tcp) {
        await _sendTcp(const {'action': 'LIST_TABLES'});
        return true;
      }
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
    _retryTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => flushQueue(),
    );
  }

  Future<void> flushQueue() async {
    if (_retryQueue.isEmpty || !await isOnline()) return;
    final pending = List<Map<String, dynamic>>.from(_retryQueue);
    _retryQueue.clear();
    for (var index = 0; index < pending.length; index++) {
      try {
        await _send(pending[index]);
      } catch (_) {
        _retryQueue.addAll(pending.skip(index));
        onLog?.call(
          'Retry interrompido; ${_retryQueue.length} comandos pendentes',
          error: true,
        );
        break;
      }
    }
    if (_retryQueue.isEmpty) {
      onLog?.call('Fila do Dataniverse reenviada com sucesso');
    }
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> body) {
    return transport == DataniverseTransport.tcp
        ? _sendTcp(body)
        : _sendHttp(body);
  }

  Future<Map<String, dynamic>> _sendHttp(
    Map<String, dynamic> body,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/command'),
      headers: {
        'Content-Type': 'application/json',
        'X-Password': password,
      },
      body: jsonEncode(body),
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        decoded['message']?.toString() ?? 'Dataniverse rejeitou o comando',
      );
    }
    return decoded;
  }

Future<Map<String, dynamic>> _sendTcp(
  Map<String, dynamic> body,
) async {
  final socket = await Socket.connect(
    tcpHost,
    tcpPort,
    timeout: const Duration(seconds: 3),
  );
  try {
    // O protocolo TCP do Dataniverse usa um JSON completo por linha.
    socket.write('${jsonEncode(body)}\n');
    await socket.flush();

    final line = await socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 10));

    return _decode(line);
  } finally {
    socket.destroy();
  }
}

  void _enqueue(Map<String, dynamic> body) {
    _retryQueue.add(body);
    startRetryLoop();
  }

  Map<String, dynamic> _decode(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};
  }

  void dispose() {
    _retryTimer?.cancel();
    _client.close();
  }
}