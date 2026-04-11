import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Debug-mode NDJSON for session 5fa30e (ingest + logcat). No secrets/PII.
// #region agent log
void agentDebugLog({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
}) {
  final payload = <String, Object?>{
    'sessionId': '5fa30e',
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  final line = jsonEncode(payload);
  debugPrint('AGENT_NDJSON: $line');
  if (kDebugMode) {
    http
        .post(
          Uri.parse(
            'http://127.0.0.1:7649/ingest/188522f9-b9e9-48f1-a9e6-0413aa6e2005',
          ),
          headers: {
            'Content-Type': 'application/json',
            'X-Debug-Session-Id': '5fa30e',
          },
          body: line,
        )
        .catchError((Object _) => http.Response('', 500));
  }
}
// #endregion agent log
