import 'dart:async';
import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;

class CustomJsExecutionResult {
  const CustomJsExecutionResult({
    required this.ok,
    required this.message,
    required this.state,
    required this.logs,
  });

  final bool ok;
  final String message;
  final Map<String, dynamic> state;
  final List<String> logs;
}

class CustomJsEngine {
  static const _timeout = Duration(seconds: 30);
  static const _memoryLimitBytes = 32 * 1024 * 1024;
  static const _timeoutSignalDelay = Duration(milliseconds: 29500);
  static const _httpSafetyMargin = Duration(seconds: 1);

  Future<CustomJsExecutionResult> execute({
    required String code,
    required Map<String, dynamic> state,
  }) async {
    final initialState = Map<String, dynamic>.from(state);
    final logs = <String>[];
    final pendingHttpRequests = <Future<void>>[];
    final stopwatch = Stopwatch()..start();
    final client = http.Client();
    final timeoutSignal = Completer<bool>();
    Timer? timeoutTimer;
    QuickJsRuntime2? runtime;

    try {
      runtime = QuickJsRuntime2(
        timeout: _timeout.inMilliseconds,
        memoryLimit: _memoryLimitBytes,
      );
      runtime.enableHandlePromises();
      runtime.onMessage('enxcci_job_log', (dynamic args) {
        if (args is List && args.isNotEmpty) {
          logs.add(args.first?.toString() ?? '');
        }
        return null;
      });
      runtime.onMessage('enxcci_job_http', (dynamic args) {
        final request = _request(client, args, stopwatch);
        pendingHttpRequests.add(
          request.then<void>((_) {}, onError: (Object _) {}),
        );
        return request;
      });
      runtime.onMessage('enxcci_job_timeout_wait', (_) => timeoutSignal.future);
      runtime.onMessage('enxcci_job_timeout_cancel', (_) {
        timeoutTimer?.cancel();
        return null;
      });
      timeoutTimer = Timer(_timeoutSignalDelay, () {
        if (!timeoutSignal.isCompleted) timeoutSignal.complete(true);
      });

      final evaluation = await runtime.evaluateAsync(
        _buildScript(code, initialState),
        sourceUrl: 'enxcci-custom-job.js',
      );
      if (evaluation.isError) {
        return _failure(evaluation.stringResult, initialState, logs);
      }

      runtime.executePendingJob();
      final remaining = _timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        return _failure('Script timed out after 30 seconds', initialState, logs);
      }

      final resolved = await runtime.handlePromise(
        evaluation,
        timeout: remaining,
      );
      if (resolved.isError) {
        return _failure(resolved.stringResult, initialState, logs);
      }

      final httpWait = _timeout - stopwatch.elapsed;
      if (httpWait <= Duration.zero) {
        return _failure('Script timed out after 30 seconds', initialState, logs);
      }
      await Future.wait(pendingHttpRequests).timeout(httpWait);

      final decoded = jsonDecode(resolved.stringResult);
      if (decoded is! Map) {
        return _failure('Script returned an invalid result', initialState, logs);
      }

      final updatedState = decoded['state'] is Map
          ? Map<String, dynamic>.from(decoded['state'] as Map)
          : initialState;
      return CustomJsExecutionResult(
        ok: decoded['ok'] == true,
        message: decoded['message']?.toString() ??
            'Script executed successfully',
        state: updatedState,
        logs: List<String>.unmodifiable(logs),
      );
    } on TimeoutException {
      return _failure('Script timed out after 30 seconds', initialState, logs);
    } catch (error) {
      return _failure(_errorMessage(error), initialState, logs);
    } finally {
      timeoutTimer?.cancel();
      client.close();
      try {
        runtime?.dispose();
      } catch (_) {
        // Runtime disposal must not leak a script failure into the scheduler.
      }
    }
  }

  Future<Map<String, dynamic>> _request(
    http.Client client,
    dynamic args,
    Stopwatch stopwatch,
  ) async {
    if (args is! List || args.length < 2) {
      throw const FormatException('http(method, url, ...) arguments are invalid');
    }

    final method = args[0].toString().trim().toUpperCase();
    final uri = Uri.parse(args[1].toString());
    if (method.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException('http requires a valid HTTP or HTTPS URL');
    }

    final request = http.Request(method, uri);
    final body = args.length > 2 ? args[2] : null;
    final headers = args.length > 3 ? args[3] : null;
    if (headers != null) {
      if (headers is! Map) {
        throw const FormatException('http headers must be an object');
      }
      for (final entry in headers.entries) {
        request.headers[entry.key.toString()] = entry.value.toString();
      }
    }

    if (body != null) {
      if (body is String) {
        request.body = body;
      } else {
        request.body = jsonEncode(body);
        request.headers.putIfAbsent(
          'Content-Type',
          () => 'application/json; charset=utf-8',
        );
      }
    }

    final remaining =
        _timeout - stopwatch.elapsed - _httpSafetyMargin;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Script timed out after 30 seconds');
    }

    final response = await client.send(request).timeout(remaining);
    final bodyTimeout =
        _timeout - stopwatch.elapsed - _httpSafetyMargin;
    if (bodyTimeout <= Duration.zero) {
      throw TimeoutException('Script timed out after 30 seconds');
    }
    final responseBody =
        await response.stream.bytesToString().timeout(bodyTimeout);
    return {
      'status': response.statusCode,
      'body': responseBody,
    };
  }

  String _buildScript(String code, Map<String, dynamic> state) {
    final encodedState = jsonEncode(state);
    return '''
      const __initialState = JSON.parse(${jsonEncode(encodedState)});
      let state = JSON.parse(${jsonEncode(encodedState)});
      const __formatLogValue = (value) => {
        if (typeof value === 'string') return value;
        try {
          const encoded = JSON.stringify(value);
          return encoded === undefined ? String(value) : encoded;
        } catch (_) {
          return String(value);
        }
      };
      const log = (...args) => {
        const message = args.map(__formatLogValue).join(' ');
        if (typeof sendMessage === 'function') {
          sendMessage('enxcci_job_log', JSON.stringify([message]));
        }
      };
      const http = async (method, url, body, headers) =>
        await sendMessage(
          'enxcci_job_http',
          JSON.stringify([method, url, body, headers])
        );
      const __timeoutPromise = sendMessage(
        'enxcci_job_timeout_wait',
        '{}'
      ).then((timedOut) => {
        if (timedOut) throw new Error('Script timed out after 30 seconds');
        return new Promise(() => {});
      });
      const __cancelTimeout = () =>
        sendMessage('enxcci_job_timeout_cancel', '{}');
      const __serializeState = () => {
        try {
          return JSON.parse(JSON.stringify(state));
        } catch (_) {
          return __initialState;
        }
      };
      (async () => {
        try {
          const __value = await Promise.race([
            (async () => {
            $code
            })(),
            __timeoutPromise
          ]);
          __cancelTimeout();
          const __message = __value === undefined
            ? 'Script executed successfully'
            : typeof __value === 'string'
              ? __value
              : JSON.stringify(__value);
          return JSON.stringify({
            ok: true,
            message: __message === undefined ? String(__value) : __message,
            state: __serializeState()
          });
        } catch (error) {
          __cancelTimeout();
          return JSON.stringify({
            ok: false,
            message: String(error && error.message ? error.message : error),
            state: __serializeState()
          });
        }
      })()
    ''';
  }

  CustomJsExecutionResult _failure(
    String message,
    Map<String, dynamic> state,
    List<String> logs,
  ) {
    return CustomJsExecutionResult(
      ok: false,
      message: message,
      state: Map<String, dynamic>.from(state),
      logs: List<String>.unmodifiable(logs),
    );
  }

  String _errorMessage(Object error) {
    if (error is TimeoutException) {
      return 'Script timed out after 30 seconds';
    }
    return error.toString();
  }
}
