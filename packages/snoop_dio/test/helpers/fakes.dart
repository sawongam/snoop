import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Answers every request from [responder] without touching the network.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.responder);

  final ({int status, Object? body}) Function(RequestOptions options) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final (:status, :body) = responder(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        'x-trace': <String>['abc'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio fakeDio() {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
    ..httpClientAdapter = FakeAdapter(
      (o) => switch (o.path) {
        '/missing' => (status: 404, body: <String, Object?>{'message': 'not found'}),
        _ => (
          status: 200,
          body: <String, Object?>{
            'id': 1,
            'tags': <String>['a'],
          },
        ),
      },
    );
  return dio;
}
