import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// #region agent log
/// NDJSON for Cursor debug session (share / Instagram import). No PII beyond keyword flags.
const _kPath =
    '/Users/brigan/Personal Development/KitchenOps/.cursor/debug-d3ef51.log';

void agentDebugLogShareImport({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, dynamic>? data,
}) {
  try {
    final payload = <String, dynamic>{
      'sessionId': 'd3ef51',
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      if (data != null) 'data': data,
    };
    final line = jsonEncode(payload);
    debugPrint('[share_import_debug] $line');
    File(_kPath).writeAsStringSync(
      '$line\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}
// #endregion
