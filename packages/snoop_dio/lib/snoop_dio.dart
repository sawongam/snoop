/// Dio adapter for snoop: records every call into the Network tab.
///
/// ```dart
/// dio.interceptors.insert(0, SnoopDioInterceptor(replayClient: dio));
/// ```
library;

export 'src/snoop_dio_interceptor.dart' show SnoopDioInterceptor;
