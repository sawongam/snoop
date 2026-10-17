import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// An inner client whose response body is fed by the test, chunk by chunk.
class StreamingClient extends http.BaseClient {
  StreamingClient({this.status = 200, this.headers = const <String, String>{}});

  final int status;
  final Map<String, String> headers;
  final List<http.BaseRequest> sent = <http.BaseRequest>[];
  bool closed = false;

  /// Whether the app listened to the response stream.
  bool bodyListened = false;

  /// Whether the app cancelled the response stream.
  bool bodyCancelled = false;

  /// The body: add chunks, then close.
  late final StreamController<List<int>> body = StreamController<List<int>>(
    onListen: () => bodyListened = true,
    onCancel: () => bodyCancelled = true,
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request);
    return http.StreamedResponse(body.stream, status, headers: headers, request: request);
  }

  @override
  void close() => closed = true;
}

/// Always answers with the same [response] object.
class FixedClient extends http.BaseClient {
  FixedClient(this.response);

  final http.StreamedResponse response;
  final List<http.BaseRequest> sent = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request);
    return response;
  }
}

/// Throws [error] from every `send`.
class ThrowingClient extends http.BaseClient {
  ThrowingClient(this.error, this.stack);

  final Object error;
  final StackTrace stack;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future<http.StreamedResponse>.error(error, stack);
}

/// Throws `RequestAbortedException` once the request's `abortTrigger` fires.
class AbortableClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final trigger = request is http.Abortable ? request.abortTrigger : null;
    await trigger;
    throw http.RequestAbortedException(request.url);
  }
}

List<int> utf(String text) => utf8.encode(text);

/// A response that knows the URL it finally came from.
class UrlResponse extends http.StreamedResponse implements http.BaseResponseWithUrl {
  UrlResponse(this.url) : super(const Stream<List<int>>.empty(), 200);

  @override
  final Uri url;
}
