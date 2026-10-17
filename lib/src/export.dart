import 'dart:async';
import 'dart:convert';

import 'package:snoop/src/bloc/bloc_inspector_registry.dart';
import 'package:snoop/src/bloc/state_diff.dart';
import 'package:snoop/src/dio/dio_inspector_registry.dart';
import 'package:snoop/src/logs/log_inspector_registry.dart';
import 'package:snoop/src/routes/route_inspector_registry.dart';
import 'package:snoop/src/widgets/state_tree_view.dart';

/// A file produced by the panel's export menu, handed to
/// `SnoopOverlay.onExport`.
class SnoopExport {
  /// Creates an export.
  const SnoopExport({required this.fileName, required this.mimeType, required this.contents});

  /// A suggested file name, e.g. `snoop-20261015-142301.har`.
  final String fileName;

  /// The MIME type of [contents].
  final String mimeType;

  /// The file's text.
  final String contents;
}

/// Receives an export from the panel, e.g. to open the share sheet.
typedef SnoopExportHandler = FutureOr<void> Function(SnoopExport export);

const String _creatorVersion = '0.1.0';

/// Recorded calls as a HAR 1.2 log, the format Chrome DevTools, Charles,
/// Proxyman and Postman import. Oldest call first, as HAR expects.
///
/// Headers are exported as recorded, so redacted values stay redacted.
Map<String, Object?> buildHar(Iterable<DioCallRecord> records) => <String, Object?>{
  'log': <String, Object?>{
    'version': '1.2',
    'creator': <String, Object?>{'name': 'snoop', 'version': _creatorVersion},
    'pages': <Object?>[],
    'entries': <Object?>[for (final r in records.toList().reversed) _harEntry(r)],
  },
};

Map<String, Object?> _harEntry(DioCallRecord r) {
  final ms = r.duration?.inMilliseconds ?? 0;
  final requestText = _bodyText(r.requestBody);
  final responseText = _bodyText(r.responseBody);
  return <String, Object?>{
    'startedDateTime': r.startedAt.toUtc().toIso8601String(),
    'time': ms,
    'request': <String, Object?>{
      'method': r.method,
      'url': r.uri.toString(),
      'httpVersion': 'HTTP/1.1',
      'cookies': <Object?>[],
      'headers': _harHeaders(r.requestHeaders),
      'queryString': <Object?>[
        for (final MapEntry(:key, :value) in r.uri.queryParametersAll.entries)
          for (final v in value) <String, Object?>{'name': key, 'value': v},
      ],
      if (requestText != null)
        'postData': <String, Object?>{
          'mimeType': _mimeType(r.requestHeaders, r.requestBody),
          'text': requestText,
        },
      'headersSize': -1,
      'bodySize': requestText == null ? 0 : utf8.encode(requestText).length,
    },
    'response': <String, Object?>{
      'status': r.statusCode ?? 0,
      'statusText': r.error != null && r.statusCode == null ? r.errorType ?? 'error' : '',
      'httpVersion': 'HTTP/1.1',
      'cookies': <Object?>[],
      'headers': _harHeaders(r.responseHeaders),
      'content': <String, Object?>{
        'size': r.responseBytes ?? (responseText == null ? 0 : utf8.encode(responseText).length),
        'mimeType': _mimeType(r.responseHeaders, r.responseBody),
        'text': ?responseText,
      },
      'redirectURL': '',
      'headersSize': -1,
      'bodySize': r.responseBytes ?? -1,
    },
    'cache': <String, Object?>{},
    'timings': <String, Object?>{'send': 0, 'wait': ms, 'receive': 0},
    if (r.error != null) '_error': r.error,
    if (r.isPending) '_pending': true,
    if (r.injectedFault != null) '_snoopFault': r.injectedFault!.name,
  };
}

List<Map<String, Object?>> _harHeaders(Map<String, String> headers) => <Map<String, Object?>>[
  for (final MapEntry(:key, :value) in headers.entries)
    <String, Object?>{'name': key, 'value': value},
];

String? _bodyText(Object? body) => switch (body) {
  null => null,
  String() => body,
  _ => _encode(body),
};

String _mimeType(Map<String, String> headers, Object? body) {
  for (final MapEntry(:key, :value) in headers.entries) {
    if (key.toLowerCase() == 'content-type') return value;
  }
  return body is Map || body is List ? 'application/json' : 'text/plain';
}

/// Everything recorded, as one JSON document: calls, live blocs with their
/// history and per-change diffs, log lines and navigations. Meant to be
/// attached to a bug report.
Map<String, Object?> buildSessionExport({DateTime? now}) => <String, Object?>{
  'snoop': _creatorVersion,
  'exportedAt': (now ?? DateTime.now()).toIso8601String(),
  'dio': <Object?>[for (final r in DioInspectorRegistry.instance.records) jsonFriendly(r.toJson())],
  'bloc': <Object?>[
    for (final b in BlocInspectorRegistry.instance.blocs)
      <String, Object?>{
        'name': b.name,
        'createdAt': b.createdAt.toIso8601String(),
        'definedAt': ?b.definedAt,
        'state': jsonFriendly(b.currentState),
        'changeCount': b.changeCount,
        if (b.lastError != null) 'lastError': '${b.lastError}',
        if (b.lastErrorStackTrace != null) 'lastErrorStackTrace': '${b.lastErrorStackTrace}',
        'history': <Object?>[
          for (final h in b.history)
            <String, Object?>{
              'timestamp': h.timestamp.toIso8601String(),
              if (h.event != null) 'event': '${h.event}',
              'emittedFrom': ?h.emittedFrom,
              'changes': <String>[for (final c in diffStates(h.currentState, h.nextState)) '$c'],
              'previous': jsonFriendly(h.currentState),
              'next': jsonFriendly(h.nextState),
            },
        ],
      },
  ],
  'logs': <Object?>[for (final l in LogInspectorRegistry.instance.records) l.toJson()],
  'routes': <Object?>[
    for (final r in RouteInspectorRegistry.instance.records) jsonFriendly(r.toJson()),
  ],
};

/// The calls as a HAR file, ready for [SnoopExportHandler].
SnoopExport harExport({DateTime? now}) => SnoopExport(
  fileName: 'snoop-${_stamp(now ?? DateTime.now())}.har',
  mimeType: 'application/json',
  contents: _encode(buildHar(DioInspectorRegistry.instance.records), indent: true),
);

/// The whole session as a JSON file, ready for [SnoopExportHandler].
SnoopExport sessionExport({DateTime? now}) {
  final at = now ?? DateTime.now();
  return SnoopExport(
    fileName: 'snoop-session-${_stamp(at)}.json',
    mimeType: 'application/json',
    contents: _encode(buildSessionExport(now: at), indent: true),
  );
}

String _encode(Object? value, {bool indent = false}) {
  final encoder = indent ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
  try {
    return encoder.convert(value);
  } on Object {
    return encoder.convert(jsonFriendly(value));
  }
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
}
