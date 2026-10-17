import 'dart:convert';
import 'dart:typed_data';

import 'package:snoop/src/network/network_registry.dart';
import 'package:snoop/src/safe.dart';

/// Header handling shared by every network adapter.
abstract final class SnoopHeaders {
  /// Headers redacted unless an adapter is told otherwise, so tokens and
  /// sessions stay out of copied cURL commands and exports by default.
  static const Set<String> defaultRedacted = <String>{
    'authorization',
    'cookie',
    'proxy-authorization',
    'set-cookie',
    'x-api-key',
  };

  /// Replacement shown for redacted header values.
  static const String redactedValue = '██ redacted ██';

  /// Flattens header values (a `String`, a `List<String>`, anything else) to
  /// `Map<String, String>`, joining lists with `', '` and replacing the
  /// values of headers named in [redacted] (lower-case names) with
  /// [redactedValue].
  static Map<String, String> flatten(Map<String, Object?> headers, Set<String> redacted) =>
      <String, String>{
        for (final MapEntry(:key, :value) in headers.entries)
          key: redacted.contains(key.toLowerCase()) ? redactedValue : _text(value),
      };

  /// [edited] with every [redactedValue] swapped back for the value of the
  /// same header (case-insensitive) in [sent], so a replay stays
  /// authenticated. Values with no counterpart in [sent] are kept.
  static Map<String, String> unredact(Map<String, String> edited, Map<String, Object?> sent) {
    String? sentValue(String name) {
      final lower = name.toLowerCase();
      for (final MapEntry(:key, :value) in sent.entries) {
        if (key.toLowerCase() == lower) return _text(value);
      }
      return null;
    }

    return <String, String>{
      for (final MapEntry(:key, :value) in edited.entries)
        key: value == redactedValue ? sentValue(key) ?? value : value,
    };
  }

  /// The value of header [name] in [headers], matched case-insensitively.
  static String? value(Map<String, Object?> headers, String name) {
    final lower = name.toLowerCase();
    for (final MapEntry(:key, :value) in headers.entries) {
      if (key.toLowerCase() == lower) return _text(value);
    }
    return null;
  }

  static String _text(Object? value) =>
      value is Iterable<Object?> ? value.map(SnoopSafe.string).join(', ') : SnoopSafe.string(value);
}

/// Turns a raw request or response body into something the panel can show
/// and export.
abstract final class SnoopBody {
  /// The presentable form of [raw], and whether it was cut short:
  ///
  /// * `null`, numbers, booleans, maps and non-byte lists pass through.
  /// * Strings longer than `Snoop.network.maxBodyChars` are cut.
  /// * Bytes (`Uint8List`, or a `List<int>` unless [contentType] is JSON)
  ///   are decoded as UTF-8 when [contentType] is textual or the bytes are
  ///   valid UTF-8, then JSON-decoded when the content type is JSON or the
  ///   text looks like JSON. Anything else reads `<binary, 12.3 kB>`.
  /// * A `Stream` reads `<stream>`.
  /// * Other objects pass through; adapters flatten their own types
  ///   (multipart bodies, say) first.
  static ({Object? body, bool truncated}) normalize(Object? raw, {String? contentType}) {
    final max = SnoopNetworkRegistry.instance.maxBodyChars;
    final type = contentType?.toLowerCase() ?? '';
    final json = type.contains('json');
    return switch (raw) {
      null || num() || bool() => (body: raw, truncated: false),
      String() => _cut(raw, max),
      Uint8List() => _bytes(raw, type, max),
      List<int>() when !json => _bytes(raw, type, max),
      Stream<Object?>() => (body: '<stream>', truncated: false),
      _ => (body: raw, truncated: false),
    };
  }

  /// `12.3 kB`-style size of [bytes].
  static String readableSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} kB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static ({Object? body, bool truncated}) _cut(String text, int max) => text.length <= max
      ? (body: text, truncated: false)
      : (body: text.substring(0, max), truncated: true);

  static const List<String> _binaryTypes = <String>[
    'application/octet-stream',
    'application/pdf',
    'application/zip',
    'application/gzip',
    'application/x-protobuf',
    'application/grpc',
    'audio/',
    'font/',
    'image/',
    'video/',
  ];

  static const List<String> _textTypes = <String>[
    'text/',
    'json',
    'xml',
    'javascript',
    'x-www-form-urlencoded',
    'graphql',
    'yaml',
    'csv',
    'html',
  ];

  static ({Object? body, bool truncated}) _bytes(List<int> bytes, String type, int max) {
    final binary = '<binary, ${readableSize(bytes.length)}>';
    if (bytes.isEmpty) return (body: '', truncated: false);
    if (_binaryTypes.any(type.contains) && !type.contains('svg')) {
      return (body: binary, truncated: false);
    }
    final truncated = bytes.length > max;
    final slice = truncated ? bytes.sublist(0, max) : bytes;
    final text = _utf8(slice, truncated);
    if (text == null) return (body: binary, truncated: false);
    final trimmed = text.trimLeft();
    if (!truncated &&
        (type.contains('json') || trimmed.startsWith('{') || trimmed.startsWith('['))) {
      final decoded = SnoopSafe.run(() => jsonDecode(text) as Object?);
      if (decoded != null) return (body: decoded, truncated: false);
    }
    // Valid UTF-8 holding NUL bytes, with no textual content type, is almost
    // surely binary.
    if (!_textTypes.any(type.contains) && text.contains('\u0000')) {
      return (body: binary, truncated: false);
    }
    return (body: text, truncated: truncated);
  }

  /// Strict UTF-8, or `null` when [bytes] aren't. A cut body may end inside
  /// a multi-byte character, so up to three trailing bytes may be dropped.
  static String? _utf8(List<int> bytes, bool truncated) {
    for (var drop = 0; drop <= (truncated ? 3 : 0) && drop < bytes.length; drop++) {
      try {
        return utf8.decode(drop == 0 ? bytes : bytes.sublist(0, bytes.length - drop));
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}

/// Builds an equivalent `curl` command for [r].
///
/// Redacted headers are left out and listed in a `# redacted:` comment above
/// the command, so pasting it never sends a placeholder as a token.
String buildCurl(SnoopCallRecord r) {
  String esc(String s) => s.replaceAll("'", r"'\''");
  final buffer = StringBuffer();
  final redacted = <String>[
    for (final MapEntry(:key, :value) in r.requestHeaders.entries)
      if (value == SnoopHeaders.redactedValue) key,
  ];
  for (final name in redacted) {
    buffer.writeln('# redacted: $name');
  }
  final body = r.requestBody;
  if (r.requestTruncated) buffer.writeln('# body truncated by snoop');
  buffer.write("curl -X ${r.method} '${esc(r.uri.toString())}'");
  r.requestHeaders.forEach((key, value) {
    if (value != SnoopHeaders.redactedValue) buffer.write(" \\\n  -H '${esc('$key: $value')}'");
  });
  if (body != null) {
    String data;
    try {
      data = body is String ? body : jsonEncode(body);
    } on Object {
      data = SnoopSafe.string(body, max: 1 << 30);
    }
    buffer.write(" \\\n  --data-binary '${esc(data)}'");
  }
  return buffer.toString();
}
