import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:snoop/snoop.dart';
import 'package:snoop_http/src/snoop_http_client.dart';

/// Entry points that are not a client.
abstract final class SnoopHttp {
  /// Runs [body] so every `http.Client()` and top-level `http.get(...)` made
  /// inside it goes through a [SnoopHttpClient].
  ///
  /// ```dart
  /// void main() => SnoopHttp.runZoned(() => runApp(const App()));
  /// ```
  ///
  /// This covers code that creates its client with `http.Client()` or calls
  /// the top-level functions. A client built explicitly (`IOClient()`,
  /// `CupertinoClient`, …) is not affected; wrap it by hand.
  ///
  /// When [enabled] is false, [body] just runs. [redactedHeaders] and
  /// [shouldRecord] are passed on to the client.
  static R runZoned<R>(
    R Function() body, {
    bool enabled = kDebugMode,
    Set<String> redactedHeaders = SnoopHeaders.defaultRedacted,
    bool Function(http.BaseRequest request)? shouldRecord,
  }) {
    if (!enabled) return body();
    // The factory is bound to the zone `runWithClient` is called from, so the
    // `http.Client()` in it is the platform client, not this factory again.
    return http.runWithClient(
      body,
      () => SnoopHttpClient(
        http.Client(),
        enabled: enabled,
        redactedHeaders: redactedHeaders,
        shouldRecord: shouldRecord,
      ),
    );
  }
}
