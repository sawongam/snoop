import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/retry.dart';
import 'package:http/testing.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_http/snoop_http.dart';

import 'helpers/fakes.dart';

final Uri _url = Uri.parse('https://api.example.com/items?page=2');

http.Response _json(String body, [int status = 200]) =>
    http.Response(body, status, headers: <String, String>{'content-type': 'application/json'});

MockClient _mock([http.Response Function(http.Request request)? respond]) =>
    MockClient((request) async => (respond ?? (_) => _json('{"id":1}'))(request));

void main() {
  final registry = Snoop.network;

  setUp(() {
    Snoop.reset();
    registry.maxRecords = 100;
    registry.maxBodyChars = 256 * 1024;
  });

  SnoopHttpClient wrap(http.Client inner, {bool closeInner = true}) =>
      SnoopHttpClient(inner, enabled: true, closeInner: closeInner);

  group('recording', () {
    test('get, post, read and readBytes are each recorded once', () async {
      final client = wrap(_mock());

      await client.get(_url);
      await client.post(_url, body: 'x');
      await client.read(_url);
      await client.readBytes(_url);
      await client.put(_url);
      await client.delete(_url);
      await client.head(_url);
      await client.patch(_url);

      expect(registry.count, 8);
      expect(registry.records.reversed.map((r) => r.method), <String>[
        'GET',
        'POST',
        'GET',
        'GET',
        'PUT',
        'DELETE',
        'HEAD',
        'PATCH',
      ]);
      expect(registry.records.every((r) => r.client == 'http' && r.completed), isTrue);
      expect(SnoopAdapters.ids, contains('http'));
    });

    test('records status, headers, body, timing and the final url', () async {
      final client = wrap(_mock((_) => _json('{"id":1,"tags":["a"]}')));

      await client.post(
        _url,
        headers: <String, String>{'content-type': 'application/json', 'x-late': 'yes'},
        body: '{"name":"tea"}',
      );

      final r = registry.records.single;
      expect(r.uri, _url);
      expect(r.statusCode, 200);
      expect(r.completed, isTrue);
      expect(r.isError, isFalse);
      expect(r.duration, isNotNull);
      expect(r.requestBody, <String, Object?>{'name': 'tea'});
      expect(r.requestBytes, 14);
      expect(r.requestHeaders['x-late'], 'yes');
      expect(r.responseBody, <String, Object?>{
        'id': 1,
        'tags': <String>['a'],
      });
      expect(r.responseHeaders['content-type'], 'application/json');
    });

    test('a 404 is an error', () async {
      final client = wrap(_mock((_) => _json('{"message":"nope"}', 404)));

      final response = await client.get(_url);

      expect(response.statusCode, 404);
      final r = registry.records.single;
      expect(r.isError, isTrue);
      expect(r.responseBody, <String, Object?>{'message': 'nope'});
    });

    test('a GET has no request body', () async {
      await wrap(_mock()).get(_url);
      expect(registry.records.single.requestBody, isNull);
    });

    test('text and binary bodies', () async {
      final client = wrap(_mock((_) => http.Response.bytes(<int>[0, 1, 2, 255], 200)));

      await client.post(_url, body: 'plain words');
      await client.post(
        _url,
        headers: <String, String>{'content-type': 'application/octet-stream'},
        body: <int>[0, 159, 146, 150],
      );

      expect(registry.records.last.requestBody, 'plain words');
      expect(registry.records.last.responseBody, '<binary, 4 B>');
      expect(registry.records.first.requestBody, '<binary, 4 B>');
    });

    test('multipart shows fields and files without reading the file stream', () async {
      var read = false;
      final stream = (StreamController<List<int>>(onListen: () => read = true)).stream;
      final request = http.MultipartRequest('POST', _url)
        ..fields['title'] = 'cat'
        ..files.add(http.MultipartFile('photo', stream, 2048, filename: 'cat.jpg'));
      final client = wrap(StreamingClient());

      unawaited(client.send(request));
      await Future<void>.delayed(Duration.zero);

      final r = registry.records.single;
      expect(r.requestBody, <String, Object?>{
        'fields': <String, String>{'title': 'cat'},
        'files': <String>['photo: cat.jpg (2.0 kB)'],
      });
      expect(r.canReplay, isFalse);
      // Only the real client reads the file; Snoop never did.
      expect(read, isFalse);
    });

    test('a streamed request shows <stream> and cannot be replayed', () async {
      final request = http.StreamedRequest('POST', _url)..sink.add(<int>[1, 2]);
      unawaited(request.sink.close());
      final client = wrap(_mock());

      await client.send(request);

      final r = registry.records.single;
      expect(r.requestBody, '<stream>');
      expect(r.canReplay, isFalse);
    });

    test('redacts auth and cookie headers by default, and custom ones', () async {
      final client = wrap(_mock());
      final custom = SnoopHttpClient(_mock(), enabled: true, redactedHeaders: <String>{'X-Mine'});

      await client.get(
        _url,
        headers: <String, String>{'Authorization': 'Bearer secret', 'Cookie': 'sid=1'},
      );
      await custom.get(_url, headers: <String, String>{'x-mine': 'secret', 'accept': 'a'});

      final first = registry.records.last.requestHeaders;
      expect(first.values, isNot(contains(contains('secret'))));
      expect(first['Authorization'], SnoopHeaders.redactedValue);
      final second = registry.records.first.requestHeaders;
      expect(second['x-mine'], SnoopHeaders.redactedValue);
      expect(second['accept'], 'a');
    });

    test('shouldRecord skips calls, and a throwing predicate records', () async {
      final client = SnoopHttpClient(
        _mock(),
        enabled: true,
        shouldRecord: (r) => !r.url.path.contains('health'),
      );
      final broken = SnoopHttpClient(
        _mock(),
        enabled: true,
        shouldRecord: (r) => throw StateError('boom'),
      );

      await client.get(Uri.parse('https://x.test/health'));
      await client.get(Uri.parse('https://x.test/orders'));
      await broken.get(Uri.parse('https://x.test/other'));

      expect(registry.records.reversed.map((r) => r.uri.path), <String>['/orders', '/other']);
    });
  });

  group('response stream', () {
    test('fully read', () async {
      final inner = StreamingClient(headers: <String, String>{'content-type': 'text/plain'});
      final client = wrap(inner);

      final future = client.send(http.Request('GET', _url));
      final response = await future;
      var r = registry.records.single;
      expect(r.statusCode, 200);
      expect(r.completed, isFalse); // Headers received, body not read yet.

      final done = response.stream.bytesToString();
      inner.body
        ..add(utf('hel'))
        ..add(utf('lo'));
      await inner.body.close();

      expect(await done, 'hello');
      r = registry.records.single;
      expect(r.completed, isTrue);
      expect(r.responseBody, 'hello');
      expect(r.responseBytes, 5);
      expect(r.responseTruncated, isFalse);
    });

    test('read partially, then cancelled', () async {
      final inner = StreamingClient(headers: <String, String>{'content-type': 'text/plain'});
      final client = wrap(inner);
      final response = await client.send(http.Request('GET', _url));

      final seen = Completer<void>();
      final subscription = response.stream.listen((_) => seen.complete());
      inner.body.add(utf('partial'));
      await seen.future;
      await subscription.cancel();

      final r = registry.records.single;
      expect(r.completed, isTrue);
      expect(r.responseBody, 'partial');
      expect(r.responseTruncated, isTrue);
      expect(inner.bodyCancelled, isTrue);
    });

    test('never read: headers received, nothing listens to the inner body', () async {
      final inner = StreamingClient();
      final client = wrap(inner);

      final response = await client.send(http.Request('GET', _url));

      final r = registry.records.single;
      expect(r.statusCode, 200);
      expect(r.duration, isNotNull);
      expect(r.completed, isFalse);
      expect(inner.bodyListened, isFalse);
      expect(response.statusCode, 200);
    });

    test('over the cap: the app gets everything, the record is cut', () async {
      registry.maxBodyChars = 10;
      final body = 'x' * 25;
      final client = wrap(_mock((_) => http.Response(body, 200)));

      final response = await client.get(_url);

      expect(response.body, body);
      final r = registry.records.single;
      expect(r.responseTruncated, isTrue);
      expect((r.responseBody as String).length, 10);
      expect(r.completed, isTrue);
    });

    test('a stream error is recorded and forwarded', () async {
      final inner = StreamingClient();
      final client = wrap(inner);
      final response = await client.send(http.Request('GET', _url));

      final result = response.stream.toList();
      inner.body.addError(const FormatException('cut off'));
      unawaited(inner.body.close());

      await expectLater(result, throwsFormatException);
      final r = registry.records.single;
      expect(r.completed, isTrue);
      expect(r.error, contains('cut off'));
      expect(r.statusCode, 200);
    });

    test('the copy keeps every response field', () async {
      final inner = MockClient(
        (request) async => http.Response(
          'ok',
          201,
          headers: <String, String>{'x-a': 'b'},
          reasonPhrase: 'Made',
          request: request,
          persistentConnection: false,
          isRedirect: true,
        ),
      );
      final client = wrap(inner);

      final response = await client.send(http.Request('GET', _url));

      expect(response.statusCode, 201);
      expect(response.reasonPhrase, 'Made');
      expect(response.headers['x-a'], 'b');
      expect(response.isRedirect, isTrue);
      expect(response.persistentConnection, isFalse);
      expect(response.contentLength, 2);
      expect(response.request?.url, _url);
    });
  });

  group('response types', () {
    test('an IOStreamedResponse stays one, so detachSocket keeps working', () async {
      final inner = FixedClient(IOStreamedResponse(const Stream<List<int>>.empty(), 101));

      final response = await wrap(inner).send(http.Request('GET', _url));

      expect(response, isA<IOStreamedResponse>());
      expect(response.statusCode, 101);
    });

    test('the final url is recorded and kept', () async {
      final final_ = Uri.parse('https://api.example.com/moved');
      final inner = FixedClient(UrlResponse(final_));

      final response = await wrap(inner).send(http.Request('GET', _url));
      await response.stream.drain<void>();

      expect(registry.records.single.finalUri, final_);
      expect(response, isA<http.BaseResponseWithUrl>());
      expect((response as http.BaseResponseWithUrl).url, final_);
    });
  });

  group('errors', () {
    test('ClientException is recorded and rethrown with its stack', () async {
      final error = http.ClientException('socket closed', _url);
      final stack = StackTrace.current;
      final client = wrap(ThrowingClient(error, stack));

      Object? caught;
      StackTrace? caughtStack;
      try {
        await client.get(_url);
      } on Object catch (e, s) {
        caught = e;
        caughtStack = s;
      }

      expect(identical(caught, error), isTrue);
      expect(caughtStack.toString(), stack.toString());
      final r = registry.records.single;
      expect(r.error, contains('socket closed'));
      expect(r.errorType, 'ClientException');
      expect(r.completed, isTrue);
      expect(r.isError, isTrue);
    });

    test('any other error is recorded with its type', () async {
      final client = wrap(ThrowingClient(StateError('weird'), StackTrace.current));

      await expectLater(client.get(_url), throwsStateError);

      expect(registry.records.single.errorType, 'StateError');
    });

    test('abortTrigger records a cancelled call', () async {
      final trigger = Completer<void>();
      final client = wrap(AbortableClient());
      final request = http.AbortableMultipartRequest('POST', _url, abortTrigger: trigger.future);

      final future = client.send(request);
      trigger.complete();

      await expectLater(future, throwsA(isA<http.RequestAbortedException>()));
      final r = registry.records.single;
      expect(r.cancelled, isTrue);
      expect(r.isError, isFalse);
      expect(r.completed, isTrue);
    });
  });

  group('simulated network conditions', () {
    setUp(() => Snoop.networkConditions.failureRate = 1);

    test('offline throws a ClientException and never sends', () async {
      final inner = StreamingClient();
      Snoop.networkConditions.fault = SnoopFault.offline;

      await expectLater(
        wrap(inner).get(_url),
        throwsA(isA<http.ClientException>().having((e) => e.message, 'message', contains('off'))),
      );

      expect(inner.sent, isEmpty);
      final r = registry.records.single;
      expect(r.injectedFault, SnoopFault.offline);
      expect(r.error, isNotNull);
      expect(r.completed, isTrue);
    });

    test('timeout throws a TimeoutException', () async {
      Snoop.networkConditions.fault = SnoopFault.timeout;

      await expectLater(wrap(StreamingClient()).get(_url), throwsA(isA<TimeoutException>()));

      expect(registry.records.single.injectedFault, SnoopFault.timeout);
    });

    for (final (fault, status) in <(SnoopFault, int)>[
      (SnoopFault.serverError, 500),
      (SnoopFault.unauthorized, 401),
    ]) {
      test('$status answers a synthetic response without sending', () async {
        final inner = StreamingClient();
        Snoop.networkConditions.fault = fault;

        final response = await wrap(inner).get(_url);

        expect(response.statusCode, status);
        expect(response.headers['x-snoop-fault'], fault.name);
        expect(response.headers['content-type'], 'application/json');
        expect(response.body, contains('Simulated by Snoop'));
        expect(inner.sent, isEmpty);
        final r = registry.records.single;
        expect(r.statusCode, status);
        expect(r.injectedFault, fault);
        expect(r.completed, isTrue);
      });
    }

    test('delay waits before sending', () async {
      Snoop.networkConditions
        ..failureRate = 0
        ..delay = const Duration(milliseconds: 30);

      await wrap(_mock()).get(_url);

      expect(registry.records.single.duration!.inMilliseconds, greaterThanOrEqualTo(25));
    });

    test('only recorded calls are affected', () async {
      Snoop.networkConditions.random = Random(1);
      final inner = _mock();

      final response = await SnoopHttpClient(inner, enabled: false).get(_url);

      expect(response.statusCode, 200);
      expect(registry.count, 0);
    });
  });

  group('wiring', () {
    test('runZoned records top-level http.get once, without recursing', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      // The test binding's HttpClient answers 400 without opening a socket.
      final response = await SnoopHttp.runZoned(
        () => http.get(Uri.parse('http://localhost:1/zoned')),
        enabled: true,
      );

      expect(response.statusCode, 400);
      final r = registry.records.single;
      expect(r.uri.path, '/zoned');
      expect(r.completed, isTrue);
      expect(SnoopAdapters.ids, contains('http'));
    });

    test('runZoned hands out a Snoop client', () {
      final client = SnoopHttp.runZoned(http.Client.new, enabled: true);
      expect(client, isA<SnoopHttpClient>());
      client.close();
    });

    test('runZoned: enabled false just runs the body', () {
      expect(SnoopHttp.runZoned(http.Client.new, enabled: false), isNot(isA<SnoopHttpClient>()));
    });

    test('RetryClient around the Snoop client records each attempt', () async {
      var attempts = 0;
      final inner = _mock((_) => ++attempts < 3 ? _json('{}', 503) : _json('{"ok":true}'));
      final client = RetryClient(
        wrap(inner),
        delay: (_) => Duration.zero,
        when: (response) => response.statusCode == 503,
      );

      final response = await client.get(_url);

      expect(response.statusCode, 200);
      expect(registry.records.reversed.map((r) => r.statusCode), <int?>[503, 503, 200]);
    });

    test('close respects closeInner', () {
      final closing = StreamingClient();
      final keeping = StreamingClient();

      wrap(closing).close();
      wrap(keeping, closeInner: false).close();

      expect(closing.closed, isTrue);
      expect(keeping.closed, isFalse);
    });

    test('disabled sends the request untouched and returns the same response', () async {
      Snoop.reset();
      final inner = FixedClient(http.StreamedResponse(const Stream<List<int>>.empty(), 200));
      final client = SnoopHttpClient(inner, enabled: false);
      final request = http.Request('GET', _url);

      final response = await client.send(request);

      expect(identical(inner.sent.single, request), isTrue);
      expect(identical(response, inner.response), isTrue);
      expect(registry.count, 0);
      expect(SnoopAdapters.ids, isEmpty);
    });

    test('x-snoop-recorded: not recorded, header stripped', () async {
      final inner = StreamingClient();
      final request = http.Request('GET', _url)..headers['x-snoop-recorded'] = '1';

      await wrap(inner).send(request);

      expect(registry.count, 0);
      expect(inner.sent.single.headers.keys, isNot(contains('x-snoop-recorded')));
    });

    test('x-snoop-recorded is stripped when disabled and on finalized requests', () async {
      final inner = StreamingClient();
      final request = http.Request('GET', _url)
        ..headers['X-Snoop-Recorded'] = '1'
        ..finalize();

      await SnoopHttpClient(inner, enabled: false).send(request);

      expect(inner.sent.single.headers, isEmpty);
    });
  });

  group('replay', () {
    test('resends through the wrapper and links the new record', () async {
      final bodies = <String>[];
      final client = wrap(
        _mock((r) {
          bodies.add(r.body);
          return _json('{"ok":true}');
        }),
      );

      await client.post(
        _url,
        headers: <String, String>{'content-type': 'application/json'},
        body: '{"name":"tea"}',
      );
      final original = registry.records.single;
      final replayed = await original.replay();

      expect(replayed, isNotNull);
      expect(replayed!.id, isNot(original.id));
      expect(replayed.replayOf, original.id);
      expect(replayed.statusCode, 200);
      expect(replayed.completed, isTrue);
      expect(registry.count, 2);
      expect(bodies, <String>['{"name":"tea"}', '{"name":"tea"}']);
    });

    test('sends edits, restoring redacted header values', () async {
      final seen = <http.Request>[];
      final client = wrap(
        _mock((r) {
          seen.add(r);
          return _json('{}');
        }),
      );
      await client.post(
        _url,
        headers: <String, String>{'authorization': 'Bearer secret'},
        body: 'old',
      );
      final original = registry.records.single;

      await original.replay(
        SnoopReplayRequest(
          method: 'put',
          uri: Uri.parse('https://api.example.com/other'),
          headers: Map<String, String>.of(original.requestHeaders),
          body: <String, Object?>{'a': 1},
        ),
      );

      final sent = seen.last;
      expect(sent.method, 'PUT');
      expect(sent.url.path, '/other');
      expect(sent.headers['authorization'], 'Bearer secret');
      expect(sent.body, '{"a":1}');
      expect(registry.records.first.replayOf, original.id);
    });

    test('a replay that fails is still recorded', () async {
      var first = true;
      final client = wrap(
        MockClient((request) async {
          if (first) {
            first = false;
            return _json('{}');
          }
          throw http.ClientException('down', request.url);
        }),
      );
      await client.get(_url);

      final replayed = await registry.records.single.replay();

      expect(replayed!.error, contains('down'));
    });
  });

  testWidgets('a call shows up in the overlay Network tab', (tester) async {
    final client = wrap(_mock());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SnoopOverlay(child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    );

    await tester.runAsync(() => client.get(_url));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('snoop.bubble')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Network 1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('/items'), findsWidgets);
    expect(find.text('200'), findsOneWidget);
  });
}
