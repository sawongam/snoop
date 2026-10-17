import 'package:http/http.dart' as http;
import 'package:snoop_http/src/wrap_stub.dart'
    if (dart.library.io) 'package:snoop_http/src/wrap_io.dart';

/// A copy of [original] that carries [stream] instead of its own body.
///
/// Every field is kept, including the final URL when the inner client
/// reports one, and the `dart:io` response type where there is one.
http.StreamedResponse copyResponse(http.StreamedResponse original, Stream<List<int>> stream) {
  final io = wrapIoResponse(original, stream);
  if (io != null) return io;
  if (original is http.BaseResponseWithUrl) {
    return _UrlResponse(original, stream, (original as http.BaseResponseWithUrl).url);
  }
  return _plain(original, stream);
}

http.StreamedResponse _plain(http.StreamedResponse original, Stream<List<int>> stream) =>
    http.StreamedResponse(
      stream,
      original.statusCode,
      contentLength: original.contentLength,
      request: original.request,
      headers: original.headers,
      isRedirect: original.isRedirect,
      persistentConnection: original.persistentConnection,
      reasonPhrase: original.reasonPhrase,
    );

class _UrlResponse extends http.StreamedResponse implements http.BaseResponseWithUrl {
  _UrlResponse(http.StreamedResponse original, Stream<List<int>> stream, this.url)
    : super(
        stream,
        original.statusCode,
        contentLength: original.contentLength,
        request: original.request,
        headers: original.headers,
        isRedirect: original.isRedirect,
        persistentConnection: original.persistentConnection,
        reasonPhrase: original.reasonPhrase,
      );

  @override
  final Uri url;
}
