import 'dart:convert';
import 'dart:io';

HttpServer? _server;

/// Starts (once) a tiny JSON API on 127.0.0.1 and returns its base URI.
///
/// `GET /posts`, `POST /posts` (echo), `GET /fail` (500) and `GET /slow`.
Future<Uri> startFakeServer() async {
  final running = _server ?? await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  if (_server == null) {
    _server = running;
    running.listen(_handle);
  }
  return Uri(scheme: 'http', host: '127.0.0.1', port: running.port);
}

/// Stops the server started by [startFakeServer].
Future<void> stopFakeServer() async {
  final server = _server;
  _server = null;
  await server?.close(force: true);
}

Future<void> _handle(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  final response = request.response..headers.contentType = ContentType.json;
  switch ((request.method, request.uri.path)) {
    case ('GET', '/posts'):
      response.write(
        jsonEncode(<Object?>[
          <String, Object?>{'id': 1, 'title': 'Hello from the fake server'},
          <String, Object?>{'id': 2, 'title': 'No internet needed'},
        ]),
      );
    case ('POST', '/posts'):
      response
        ..statusCode = HttpStatus.created
        ..write(jsonEncode(<String, Object?>{'id': 3, 'echo': body}));
    case ('GET', '/slow'):
      await Future<void>.delayed(const Duration(milliseconds: 300));
      response.write(jsonEncode(<String, Object?>{'slow': true}));
    case ('GET', '/fail'):
      response
        ..statusCode = HttpStatus.internalServerError
        ..write(jsonEncode(<String, Object?>{'error': 'simulated failure'}));
    default:
      response
        ..statusCode = HttpStatus.notFound
        ..write(jsonEncode(<String, Object?>{'error': 'not found'}));
  }
  await response.close();
}
