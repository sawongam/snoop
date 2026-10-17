import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// A copy of [original] over [stream] that is still an [IOStreamedResponse],
/// so `detachSocket` (WebSocket upgrades) keeps working. `null` when
/// [original] is something else.
http.StreamedResponse? wrapIoResponse(http.StreamedResponse original, Stream<List<int>> stream) {
  if (original is! IOStreamedResponse) return null;
  if (original is http.BaseResponseWithUrl) {
    return _IoTeeWithUrl(original, stream, (original as http.BaseResponseWithUrl).url);
  }
  return _IoTee(original, stream);
}

class _IoTee extends IOStreamedResponse {
  _IoTee(this._original, Stream<List<int>> stream)
    : super(
        stream,
        _original.statusCode,
        contentLength: _original.contentLength,
        request: _original.request,
        headers: _original.headers,
        isRedirect: _original.isRedirect,
        persistentConnection: _original.persistentConnection,
        reasonPhrase: _original.reasonPhrase,
      );

  final IOStreamedResponse _original;

  @override
  Future<Socket> detachSocket() => _original.detachSocket();
}

class _IoTeeWithUrl extends _IoTee implements http.BaseResponseWithUrl {
  _IoTeeWithUrl(super.original, super.stream, this.url);

  @override
  final Uri url;
}
