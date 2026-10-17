import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:snoop/snoop.dart';
import 'package:snoop_chopper/snoop_chopper.dart';

import 'helpers/fakes.dart';

void main() {
  final registry = Snoop.network;

  setUp(() {
    Snoop.reset();
    registry.maxRecords = 100;
  });

  tearDown(() => Snoop.networkConditions.reset());

  ChopperClient clientWith(
    Server server, {
    SnoopChopperInterceptor? snoop,
    Authenticator? authenticator,
    List<Interceptor> before = const <Interceptor>[],
    List<Interceptor> after = const <Interceptor>[],
  }) => chopperFor(
    server,
    interceptors: <Interceptor>[
      ...before,
      snoop ?? SnoopChopperInterceptor(enabled: true),
      ...after,
    ],
    authenticator: authenticator,
  );

  group('recording', () {
    test('records a JSON call as the encoded string, with headers and timing', () async {
      final chopper = clientWith(Server(), before: [HeaderInterceptor('x-late', 'yes')]);

      await chopper.post<dynamic, dynamic>(
        Uri.parse('/items'),
        body: <String, Object?>{'name': 'tea'},
        parameters: <String, Object?>{'page': 2},
      );

      final r = registry.records.single;
      expect(r.client, 'chopper');
      expect(r.method, 'POST');
      expect(r.uri.toString(), 'https://api.example.com/items?page=2');
      expect(r.requestBody, '{"name":"tea"}');
      expect(r.statusCode, 200);
      expect(r.completed, isTrue);
      expect(r.isError, isFalse);
      expect(r.duration, isNotNull);
      expect(r.responseBody, '{"id":1,"tags":["a"]}');
      expect(r.requestHeaders['x-late'], 'yes');
      expect(r.requestHeaders['content-type'], contains('application/json'));
      expect(r.responseHeaders['x-trace'], 'abc');
      expect(SnoopAdapters.ids, contains('chopper'));
    });

    test('records the typed error body of a failed call', () async {
      final chopper = clientWith(Server());

      final response = await chopper.get<dynamic, dynamic>(Uri.parse('/missing'));

      expect(response.statusCode, 404);
      final r = registry.records.single;
      expect(r.statusCode, 404);
      expect(r.isError, isTrue);
      expect(r.responseBody, '{"message":"not found"}');
      expect(registry.errorCount, 1);
    });

    test('redacts auth headers by default and honors a custom set', () async {
      final chopper = clientWith(
        Server(),
        before: [HeaderInterceptor('Authorization', 'Bearer secret')],
      );
      await chopper.get<dynamic, dynamic>(Uri.parse('/me'));
      expect(registry.records.single.requestHeaders['Authorization'], SnoopHeaders.redactedValue);

      Snoop.reset();
      final custom = clientWith(
        Server(),
        snoop: SnoopChopperInterceptor(enabled: true, redactedHeaders: {'X-Session'}),
        before: [HeaderInterceptor('x-session', 's3cret'), HeaderInterceptor('x-ok', 'plain')],
      );
      await custom.get<dynamic, dynamic>(Uri.parse('/me'));
      final headers = registry.records.single.requestHeaders;
      expect(headers['x-session'], SnoopHeaders.redactedValue);
      expect(headers['x-ok'], 'plain');
    });

    test('does nothing when disabled', () async {
      final chopper = clientWith(Server(), snoop: SnoopChopperInterceptor(enabled: false));

      final response = await chopper.get<dynamic, dynamic>(Uri.parse('/items'));

      expect(response.statusCode, 200);
      expect(registry.records, isEmpty);
      expect(SnoopAdapters.ids, isNot(contains('chopper')));
    });

    test('shouldRecord skips calls, and a throwing predicate records', () async {
      final chopper = clientWith(
        Server(),
        snoop: SnoopChopperInterceptor(
          enabled: true,
          shouldRecord: (request) => !request.url.path.startsWith('/health'),
        ),
      );
      await chopper.get<dynamic, dynamic>(Uri.parse('/health'));
      await chopper.get<dynamic, dynamic>(Uri.parse('/items'));
      expect(registry.records.map((r) => r.uri.path), <String>['/items']);

      Snoop.reset();
      final broken = clientWith(
        Server(),
        snoop: SnoopChopperInterceptor(enabled: true, shouldRecord: (_) => throw StateError('x')),
      );
      await broken.get<dynamic, dynamic>(Uri.parse('/items'));
      expect(registry.records, hasLength(1));
    });

    test('marks requests for snoop_http only when it is installed', () async {
      final server = Server();
      final chopper = clientWith(server);
      await chopper.get<dynamic, dynamic>(Uri.parse('/items'));
      expect(server.requests.single.headers, isNot(contains('x-snoop-recorded')));

      SnoopAdapters.register('http', SnoopAdapterKind.network);
      await chopper.get<dynamic, dynamic>(Uri.parse('/items'));
      expect(server.requests.last.headers['x-snoop-recorded'], '1');
      for (final r in registry.records) {
        expect(r.requestHeaders, isNot(contains('x-snoop-recorded')));
      }
    });
  });

  group('bodies', () {
    test('multipart shows filenames and sizes without reading the file', () async {
      final stream = WatchedStream();
      final file = http.MultipartFile('avatar', stream, 2048, filename: 'me.png');
      final request = Request(
        'POST',
        Uri.parse('/upload'),
        Uri.parse('https://api.example.com'),
        multipart: true,
        parts: <PartValue<Object?>>[
          const PartValue<Object?>('title', 'hello'),
          PartValue<Object?>('avatar', file),
          const PartValueFile<String>('doc', '/tmp/notes.txt'),
          PartValue<Object?>('bad', Unprintable()),
        ],
      );
      final chain = FakeChain<String>(
        request,
        () => Response<String>(http.Response('ok', 200), 'ok'),
      );

      await SnoopChopperInterceptor(enabled: true).intercept<String>(chain);

      final body = registry.records.single.requestBody! as Map<String, Object?>;
      expect(body['fields'], containsPair('title', 'hello'));
      expect(body['fields'], containsPair('bad', contains('toString threw')));
      expect(body['files'], <String>['avatar: me.png (2.0 kB)', 'doc: /tmp/notes.txt']);
      expect(stream.listened, isFalse);
      expect(registry.records.single.canReplay, isFalse);
    });

    test('a streamed response is not consumed', () async {
      final stream = WatchedStream();
      final request = Request('GET', Uri.parse('/video'), Uri.parse('https://api.example.com'));
      final chain = FakeChain<Stream<List<int>>>(
        request,
        () => Response<Stream<List<int>>>(
          http.StreamedResponse(stream, 200, contentLength: 99),
          stream,
        ),
      );

      final response = await SnoopChopperInterceptor(enabled: true).intercept(chain);

      expect(response.body, same(stream));
      expect(stream.listened, isFalse);
      final r = registry.records.single;
      expect(r.responseBody, '<stream>');
      expect(r.responseBytes, 99);
      expect(r.statusCode, 200);
    });

    test('a typed body falls back to the raw response text', () async {
      final request = Request('GET', Uri.parse('/item'), Uri.parse('https://api.example.com'));
      final chain = FakeChain<Object>(
        request,
        () => Response<Object>(
          http.Response('{"id":7}', 200, headers: {'content-type': 'application/json'}),
          Unprintable(),
        ),
      );

      await SnoopChopperInterceptor(enabled: true).intercept(chain);

      expect(registry.records.single.responseBody, '{"id":7}');
    });

    test('a typed body with no raw text goes through jsonFriendly', () async {
      final request = Request('GET', Uri.parse('/item'), Uri.parse('https://api.example.com'));
      final chain = FakeChain<Object>(
        request,
        () => Response<Object>(
          http.StreamedResponse(const Stream<List<int>>.empty(), 200),
          Unprintable(),
        ),
      );

      await SnoopChopperInterceptor(enabled: true).intercept(chain);

      expect(registry.records.single.responseBody, contains('toString threw'));
    });
  });

  group('errors', () {
    test('rethrows a ChopperHttpException unchanged and records its response', () async {
      final response = Response<dynamic>(
        http.Response('{"m":1}', 422, headers: {'content-type': 'application/json'}),
        null,
        error: 'bad',
      );
      final error = ChopperHttpException(response);
      final chopper = clientWith(Server(), after: [ThrowingInterceptor(error)]);

      await expectLater(chopper.get<dynamic, dynamic>(Uri.parse('/items')), throwsA(same(error)));

      final r = registry.records.single;
      expect(r.statusCode, 422);
      expect(r.errorType, 'ChopperHttpException');
      expect(r.error, isNotNull);
      expect(r.responseBody, 'bad');
      expect(r.completed, isTrue);
    });

    test('rethrows a ClientException unchanged', () async {
      final error = http.ClientException('socket closed', Uri.parse('https://api.example.com'));
      final chopper = clientWith(Server(), after: [ThrowingInterceptor(error)]);

      await expectLater(chopper.get<dynamic, dynamic>(Uri.parse('/items')), throwsA(same(error)));

      final r = registry.records.single;
      expect(r.error, 'socket closed');
      expect(r.errorType, 'ClientException');
      expect(r.statusCode, isNull);
      expect(r.isError, isTrue);
    });

    test('an aborted request is cancelled, not failed', () async {
      final chopper = clientWith(
        Server(),
        after: [ThrowingInterceptor(http.RequestAbortedException())],
      );

      await expectLater(
        chopper.get<dynamic, dynamic>(Uri.parse('/items')),
        throwsA(isA<http.RequestAbortedException>()),
      );

      final r = registry.records.single;
      expect(r.cancelled, isTrue);
      expect(r.error, isNull);
      expect(r.isError, isFalse);
    });

    test('a throwing toString never breaks the app', () async {
      final chopper = clientWith(Server(), after: [ThrowingInterceptor(Unprintable())]);

      await expectLater(
        chopper.get<dynamic, dynamic>(Uri.parse('/items')),
        throwsA(isA<Unprintable>()),
      );

      expect(registry.records.single.error, contains('toString threw'));
    });
  });

  group('network conditions', () {
    test('a simulated 500 answers without reaching the server', () async {
      Snoop.networkConditions
        ..failureRate = 1
        ..fault = SnoopFault.serverError;
      final server = Server();
      final chopper = clientWith(server);

      final response = await chopper.get<dynamic, dynamic>(Uri.parse('/items'));

      expect(response.statusCode, 500);
      expect(response.isSuccessful, isFalse);
      expect((response.error! as Map<String, Object?>)['status'], 500);
      expect(server.requests, isEmpty);
      final r = registry.records.single;
      expect(r.statusCode, 500);
      expect(r.injectedFault, SnoopFault.serverError);
      expect(r.responseHeaders['x-snoop-fault'], 'serverError');
      expect(r.isError, isTrue);
    });

    test('offline throws a ClientException and timeout a TimeoutException', () async {
      Snoop.networkConditions
        ..failureRate = 1
        ..fault = SnoopFault.offline;
      final chopper = clientWith(Server());

      await expectLater(
        chopper.get<dynamic, dynamic>(Uri.parse('/items')),
        throwsA(isA<http.ClientException>()),
      );
      expect(registry.records.single.injectedFault, SnoopFault.offline);
      expect(registry.records.single.errorType, 'ClientException');

      Snoop.reset();
      Snoop.networkConditions
        ..failureRate = 1
        ..fault = SnoopFault.timeout;
      final other = clientWith(Server());
      await expectLater(
        other.get<dynamic, dynamic>(Uri.parse('/items')),
        throwsA(isA<TimeoutException>()),
      );
      expect(registry.records.single.injectedFault, SnoopFault.timeout);
      expect(registry.records.single.errorType, 'TimeoutException');
    });

    test('latency delays the call, which then succeeds', () async {
      Snoop.networkConditions.delay = const Duration(milliseconds: 30);
      final chopper = clientWith(Server());

      await chopper.get<dynamic, dynamic>(Uri.parse('/items'));

      final r = registry.records.single;
      expect(r.statusCode, 200);
      expect(r.duration!, greaterThanOrEqualTo(const Duration(milliseconds: 30)));
      expect(r.injectedFault, isNull);
    });
  });

  group('authenticator', () {
    test('a retried call is one record with the final status', () async {
      final server = Server();
      final chopper = clientWith(server, authenticator: FakeAuthenticator());

      final response = await chopper.get<dynamic, dynamic>(Uri.parse('/secure'));

      expect(response.statusCode, 200);
      expect(server.requests, hasLength(2)); // 401, then the retry.
      final r = registry.records.single;
      expect(r.statusCode, 200);
      expect(r.isError, isFalse);
      expect(r.requestHeaders['authorization'], SnoopHeaders.redactedValue);
    });
  });

  group('replay', () {
    test('resends through the replay client and links the new record', () async {
      final server = Server();
      late final ChopperClient chopper;
      chopper = chopperFor(
        server,
        interceptors: [SnoopChopperInterceptor(enabled: true, replayClient: () => chopper)],
      );
      await chopper.post<dynamic, dynamic>(
        Uri.parse('/items'),
        body: <String, Object?>{'name': 'tea'},
      );
      final original = registry.records.single;
      expect(original.canReplay, isTrue);

      final replayed = await original.replay();

      expect(replayed, isNotNull);
      expect(replayed!.id, isNot(original.id));
      expect(replayed.replayOf, original.id);
      expect(replayed.statusCode, 200);
      expect(replayed.uri, original.uri);
      expect(registry.records, hasLength(2));
      expect(server.bodies, <String>['{"name":"tea"}', '{"name":"tea"}']);
    });

    test('sends an edited body and the real value of redacted headers', () async {
      final server = Server();
      late final ChopperClient chopper;
      chopper = chopperFor(
        server,
        interceptors: [
          HeaderInterceptor('authorization', 'Bearer secret'),
          SnoopChopperInterceptor(enabled: true, replayClient: () => chopper),
        ],
      );
      await chopper.post<dynamic, dynamic>(Uri.parse('/items'), body: <String, Object?>{'a': 1});
      final original = registry.records.single;

      final edit = original.toReplayRequest()..body = '{"a":2}';
      final replayed = await original.replay(edit);

      expect(replayed!.statusCode, 200);
      expect(server.bodies.last, '{"a":2}');
      expect(server.requests.last.headers['authorization'], 'Bearer secret');
    });

    test('without a replay client the call cannot be replayed', () async {
      final chopper = clientWith(Server());
      await chopper.get<dynamic, dynamic>(Uri.parse('/items'));

      final r = registry.records.single;
      expect(r.canReplay, isFalse);
      expect(await r.replay(), isNull);
      expect(registry.records, hasLength(1));
    });

    test('a replay through a client without the interceptor is not recorded', () async {
      final other = chopperFor(Server());
      final chopper = chopperFor(
        Server(),
        interceptors: [SnoopChopperInterceptor(enabled: true, replayClient: () => other)],
      );
      await chopper.get<dynamic, dynamic>(Uri.parse('/items'));

      expect(await registry.records.single.replay(), isNull);
      expect(registry.records, hasLength(1));
    });
  });
}
