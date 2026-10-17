import 'dart:async';
import 'dart:convert';

import 'package:chopper/chopper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A fake server that remembers what reached it.
class Server {
  /// Requests that reached the server.
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  /// Their bodies, as text.
  final List<String> bodies = <String>[];

  /// Answers 404 for `/missing`, 401 for `/secure` without a fresh token,
  /// else 200.
  /// Called as each request reaches the server.
  void Function()? onSend;

  MockClient get client => MockClient((request) async {
    onSend?.call();
    requests.add(request);
    bodies.add(request.body);
    final (status, body) = switch (request.url.path) {
      '/missing' => (404, <String, Object?>{'message': 'not found'}),
      '/secure' when request.headers['authorization'] != 'Bearer fresh' => (
        401,
        <String, Object?>{'message': 'expired'},
      ),
      _ => (
        200,
        <String, Object?>{
          'id': 1,
          'tags': <String>['a'],
        },
      ),
    };
    return http.Response(
      jsonEncode(body),
      status,
      headers: <String, String>{'content-type': 'application/json', 'x-trace': 'abc'},
      request: request,
    );
  });
}

ChopperClient chopperFor(
  Server server, {
  List<Interceptor> interceptors = const <Interceptor>[],
  Authenticator? authenticator,
}) => ChopperClient(
  baseUrl: Uri.parse('https://api.example.com'),
  client: server.client,
  converter: const JsonConverter(),
  errorConverter: const JsonConverter(),
  interceptors: interceptors,
  authenticator: authenticator,
);

/// Adds [name]: [value] to every request.
class HeaderInterceptor implements Interceptor {
  HeaderInterceptor(this.name, this.value);

  final String name;
  final String value;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) =>
      chain.proceed(applyHeader(chain.request, name, value));
}

/// Fails every call with [error].
class ThrowingInterceptor implements Interceptor {
  ThrowingInterceptor(this.error);

  final Object error;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) => throw error;
}

/// Refreshes the token on a 401.
class FakeAuthenticator extends Authenticator {
  @override
  FutureOr<Request?> authenticate(
    Request request,
    Response<dynamic> response, [
    Request? originalRequest,
  ]) => response.statusCode == 401
      ? applyHeader(request, 'authorization', 'Bearer fresh', override: true)
      : null;
}

/// The end of a chain that answers with [respond] and never touches the
/// request body.
class FakeChain<BodyType> implements Chain<BodyType> {
  FakeChain(this.request, this.respond);

  @override
  final Request request;

  final Response<BodyType> Function() respond;

  @override
  FutureOr<Response<BodyType>> proceed(Request request) => respond();
}

/// A byte stream that records whether anyone listened.
class WatchedStream extends Stream<List<int>> {
  bool listened = false;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listened = true;
    return const Stream<List<int>>.empty().listen(onData, onDone: onDone);
  }
}

/// A value whose text can't be produced.
class Unprintable {
  @override
  String toString() => throw StateError('no text');
}
