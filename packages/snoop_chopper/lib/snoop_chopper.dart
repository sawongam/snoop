/// Chopper adapter for snoop: records every call into the Network tab.
///
/// ```dart
/// late final ChopperClient chopper;
///
/// void setUpChopper() {
///   chopper = ChopperClient(
///     baseUrl: Uri.parse('https://api.example.com'),
///     converter: const JsonConverter(),
///     interceptors: [SnoopChopperInterceptor(replayClient: () => chopper)],
///   );
/// }
/// ```
library;

export 'src/snoop_chopper_interceptor.dart' show SnoopChopperInterceptor;
