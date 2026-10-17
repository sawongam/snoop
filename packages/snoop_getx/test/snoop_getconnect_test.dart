import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_getx/snoop_getx.dart';

void main() {
  late HttpServer server;
  late String base;
  late List<Map<String, Object?>> seen;

  setUp(() async {
    Snoop.reset();
    seen = <Map<String, Object?>>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      seen.add(<String, Object?>{
        'path': request.uri.path,
        'body': body,
        'type': request.headers.contentType?.mimeType,
        'auth': request.headers.value('authorization'),
        'marker': request.headers.value('x-snoop'),
      });
      final response = request.response;
      switch (request.uri.path) {
        case '/json':
          response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(<String, Object?>{'ok': true}));
        case '/echo':
          response
            ..headers.contentType = ContentType.json
            ..write(body.isEmpty ? '{}' : body);
        case '/secure':
          if (request.headers.value('authorization') == 'Bearer fresh') {
            response.write('welcome');
          } else {
            response.statusCode = HttpStatus.unauthorized;
          }
        case '/missing':
          response
            ..statusCode = HttpStatus.notFound
            ..write('nope');
        case '/hang':
          await Future<void>.delayed(const Duration(seconds: 2));
        default:
          response.write('hi');
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  GetConnect connect({Duration timeout = const Duration(seconds: 5)}) =>
      GetConnect(timeout: timeout)
        ..baseUrl = base
        ..httpClient.timeout = timeout;

  SnoopCallRecord only() => Snoop.network.records.single;

  test('GET JSON: method, url, status, headers and decoded body', () async {
    final c = connect();
    SnoopGetConnect.attach(c, enabled: true);
    final response = await c.get<Map<String, dynamic>>('/json');
    expect(response.body, <String, Object?>{'ok': true});

    final r = only();
    expect(r.client, 'getconnect');
    expect(r.method, 'GET');
    expect(r.uri.toString(), '$base/json');
    expect(r.statusCode, 200);
    expect(r.completed, isTrue);
    expect(r.responseBody, <String, Object?>{'ok': true});
    expect(r.responseHeaders['content-type'], contains('json'));
    expect(r.requestBody, isNull);
    expect(r.duration, isNotNull);
    expect(SnoopAdapters.all['getconnect'], SnoopAdapterKind.network);
  });

  test('POST JSON: the body is recorded and still reaches the server', () async {
    final c = connect();
    SnoopGetConnect.attach(c, enabled: true);
    final response = await c.post<Map<String, dynamic>>('/echo', <String, Object?>{'a': 1});

    expect(response.body, <String, Object?>{'a': 1});
    expect(seen.single['body'], '{"a":1}');
    final r = only();
    expect(r.method, 'POST');
    expect(r.requestBody, <String, Object?>{'a': 1});
    expect(r.requestBytes, 7);
    expect(r.responseBody, <String, Object?>{'a': 1});
  });

  test('multipart: field and file names are recorded, contents are not', () async {
    final c = connect();
    SnoopGetConnect.attach(c, enabled: true);
    final form = FormData(<String, dynamic>{
      'title': 'holiday',
      'photo': MultipartFile(<int>[1, 2, 3, 4], filename: 'beach.png'),
    });
    final response = await c.post<Object?>('/json', form);
    expect(response.statusCode, 200);
    expect(seen.single['type'], 'multipart/form-data');

    final body = only().requestBody! as Map<String, Object?>;
    expect(body['fields'], <String>['title']);
    expect(body['files'], <String>['photo: beach.png']);
    expect(only().requestBody.toString(), isNot(contains('holiday')));
  });

  test('error status: recorded as a response, not an error', () async {
    final c = connect();
    SnoopGetConnect.attach(c, enabled: true);
    await c.get<String>('/missing');
    expect(only().statusCode, 404);
    expect(only().responseBody, 'nope');
    expect(only().error, isNull);
  });

  test('sensitive headers are redacted', () async {
    final c = connect();
    SnoopGetConnect.attach(c, enabled: true);
    await c.get<Object?>('/json', headers: <String, String>{'Authorization': 'Bearer secret'});
    expect(
      only().requestHeaders['Authorization'] ?? only().requestHeaders['authorization'],
      SnoopHeaders.redactedValue,
    );
    // The server still got the real value.
    expect(seen.single['auth'], 'Bearer secret');
  });

  test('network failure ends as an error once the timeout passed', () async {
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = dead.port;
    await dead.close();
    final c = GetConnect(timeout: const Duration(milliseconds: 200))
      ..baseUrl = 'http://127.0.0.1:$port';
    SnoopGetConnect.attach(c, enabled: true, failureGrace: const Duration(milliseconds: 100));

    final response = await c.get<String>('/x');
    expect(response.statusCode, isNull);
    expect(only().completed, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 600));
    final r = only();
    expect(r.completed, isTrue);
    expect(r.error, isNotNull);
    expect(r.errorType, 'noResponse');
  });

  test('timeout: a hanging server ends as an error too', () async {
    final c = connect(timeout: const Duration(milliseconds: 200));
    SnoopGetConnect.attach(c, enabled: true, failureGrace: const Duration(milliseconds: 100));
    final response = await c.get<String>('/hang');
    expect(response.statusCode, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(only().completed, isTrue);
    expect(only().error, isNotNull);
  });

  test('a 401 retried by the authenticator links the retry to the first call', () async {
    final c = connect();
    c.httpClient.addAuthenticator<Object?>((request) {
      request.headers['Authorization'] = 'Bearer fresh';
      return request;
    });
    SnoopGetConnect.attach(c, enabled: true);

    final response = await c.get<String>('/secure');
    expect(response.statusCode, 200);
    final records = Snoop.network.records.toList()..sort((a, b) => a.id.compareTo(b.id));
    expect(records, hasLength(2));
    expect(records[0].statusCode, 401);
    expect(records[0].retryOf, isNull);
    expect(records[1].statusCode, 200);
    expect(records[1].retryOf, records[0].id);
  });

  test('network conditions delay the call', () async {
    final c = connect();
    SnoopGetConnect.attach(c, enabled: true);
    Snoop.networkConditions.delay = const Duration(milliseconds: 300);
    addTearDown(Snoop.networkConditions.reset);
    await c.get<Object?>('/json');
    expect(only().duration!, greaterThanOrEqualTo(const Duration(milliseconds: 290)));
    expect(only().injectedFault, isNull);
  });

  test('shouldRecord can skip calls, and the call still works', () async {
    final c = connect();
    SnoopGetConnect.attach(c, enabled: true, shouldRecord: (r) => !r.url.path.contains('json'));
    final skipped = await c.get<Object?>('/json');
    expect(skipped.statusCode, 200);
    await c.get<String>('/other');
    expect(Snoop.network.records.single.uri.path, '/other');
  });

  test('disabled: nothing is recorded or registered and the call is unchanged', () async {
    final c = connect();
    SnoopGetConnect.attach(c, enabled: false);
    final response = await c.post<Map<String, dynamic>>('/echo', <String, Object?>{'a': 1});
    expect(response.body, <String, Object?>{'a': 1});
    expect(Snoop.network.records, isEmpty);
    expect(SnoopAdapters.has(SnoopAdapterKind.network), isFalse);
  });

  test('nothing is added to the wire', () async {
    final c = connect();
    SnoopGetConnect.attach(c, enabled: true);
    await c.get<Object?>('/json');
    expect(seen.single['marker'], isNull);
  });
}
