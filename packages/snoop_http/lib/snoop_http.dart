/// `package:http` adapter for snoop: records every call into the Network tab.
///
/// ```dart
/// final client = SnoopHttpClient(http.Client());
///
/// void main() => SnoopHttp.runZoned(() => runApp(const App()));
/// ```
library;

export 'src/snoop_http.dart' show SnoopHttp;
export 'src/snoop_http_client.dart' show SnoopHttpClient;
