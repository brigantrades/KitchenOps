import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const _kSessionId = '3e34f6';
const _kLogPath =
    '/Users/brigan/Personal Development/KitchenOps/.cursor/debug-3e34f6.log';
const _kIngestUri =
    'http://127.0.0.1:7665/ingest/8958ce1e-f127-4a23-8040-af744424700a';

/// Debug-mode NDJSON (session 3e34f6). No secrets: never log full FCM tokens.
void agentSessionLog({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?>? data,
  String runId = 'pre-fix',
}) {
  unawaited(_agentSessionLogAsync(
    hypothesisId: hypothesisId,
    location: location,
    message: message,
    data: data,
    runId: runId,
  ));
}

Future<void> _agentSessionLogAsync({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?>? data,
  required String runId,
}) async {
  final payload = <String, Object?>{
    'sessionId': _kSessionId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data ?? const <String, Object?>{},
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'runId': runId,
  };
  final line = jsonEncode(payload);
  debugPrint('AGENT_SESSION_LOG $line');
  if (!kIsWeb) {
    try {
      final f = File(_kLogPath);
      await f.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
  try {
    await http
        .post(
          Uri.parse(_kIngestUri),
          headers: const {
            'Content-Type': 'application/json',
            'X-Debug-Session-Id': _kSessionId,
          },
          body: line,
        )
        .timeout(const Duration(seconds: 3));
  } catch (_) {}
}
