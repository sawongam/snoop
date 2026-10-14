import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

import 'helpers/fakes.dart';

void main() {
  final registry = Snoop.dio;

  setUp(() {
    Snoop.reset();
    registry.maxRecords = 100;
  });

  test('records a successful call with headers, body and timing', () async {
    final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: true));
    // Added after the inspector: its headers must still show up.
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          o.headers['x-late'] = 'yes';
          h.next(o);
        },
      ),
    );

    await dio.post<Object?>('/items', data: <String, Object?>{'name': 'tea'});

    final r = registry.records.single;
    expect(r.method, 'POST');
    expect(r.uri.toString(), 'https://api.example.com/items');
    expect(r.statusCode, 200);
    expect(r.completed, isTrue);
    expect(r.isError, isFalse);
    expect(r.duration, isNotNull);
    expect(r.requestBody, <String, Object?>{'name': 'tea'});
    expect(r.responseBody, <String, Object?>{
      'id': 1,
      'tags': <String>['a'],
    });
    expect(r.requestHeaders['x-late'], 'yes');
    expect(r.responseHeaders['x-trace'], 'abc');
  });

  test('records failed calls', () async {
    final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: true));

    await expectLater(dio.get<Object?>('/missing'), throwsA(isA<DioException>()));

    final r = registry.records.single;
    expect(r.statusCode, 404);
    expect(r.isError, isTrue);
    expect(r.errorType, 'badResponse');
    expect(r.responseBody, <String, Object?>{'message': 'not found'});
    expect(registry.errorCount, 1);
  });

  test('redacts configured headers case-insensitively', () async {
    final dio = fakeDio()
      ..interceptors.add(
        SnoopDioInterceptor(enabled: true, redactedHeaders: <String>{'Authorization'}),
      );

    await dio.get<Object?>(
      '/me',
      options: Options(headers: <String, Object?>{'authorization': 'Bearer secret'}),
    );

    final headers = registry.records.single.requestHeaders;
    expect(headers['authorization'], SnoopDioInterceptor.redactedValue);
    expect(headers.values, isNot(contains(contains('secret'))));
  });

  test('redacts auth and cookie headers by default', () async {
    final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: true));

    await dio.get<Object?>(
      '/me',
      options: Options(
        headers: <String, Object?>{'Authorization': 'Bearer secret', 'Cookie': 'sid=secret'},
      ),
    );

    final headers = registry.records.single.requestHeaders;
    expect(headers['Authorization'], SnoopDioInterceptor.redactedValue);
    expect(headers['Cookie'], SnoopDioInterceptor.redactedValue);
    expect(headers.values, isNot(contains(contains('secret'))));
  });

  test('an empty redactedHeaders set disables redaction', () async {
    final dio = fakeDio()
      ..interceptors.add(SnoopDioInterceptor(enabled: true, redactedHeaders: <String>{}));

    await dio.get<Object?>(
      '/me',
      options: Options(headers: <String, Object?>{'authorization': 'Bearer secret'}),
    );

    expect(registry.records.single.requestHeaders['authorization'], 'Bearer secret');
  });

  test('flattens FormData and honours shouldRecord', () async {
    final dio = fakeDio()
      ..interceptors.add(
        SnoopDioInterceptor(enabled: true, shouldRecord: (o) => o.path != '/health'),
      );

    await dio.get<Object?>('/health');
    await dio.post<Object?>('/upload', data: FormData.fromMap(<String, Object?>{'a': '1'}));

    final r = registry.records.single;
    expect(r.uri.path, '/upload');
    expect(r.requestBody, <String, Object?>{
      'fields': <String, String>{'a': '1'},
      'files': <String>[],
    });
  });

  test('add keeps newest first and is bounded by maxRecords; clear empties it', () {
    registry.maxRecords = 2;
    for (var i = 0; i < 3; i++) {
      registry.add(
        DioCallRecord(
          id: registry.nextId(),
          method: 'GET',
          uri: Uri.parse('https://x.dev/$i'),
          startedAt: DateTime(2026),
        ),
      );
    }
    expect(registry.records.map((r) => r.uri.path), <String>['/2', '/1']);

    registry.clear();
    expect(registry.count, 0);
  });

  test('records nothing when disabled', () async {
    final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: false));
    await dio.get<Object?>('/items');
    expect(registry.count, 0);
  });

  test('toJson exports the call', () async {
    final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: true));
    await dio.get<Object?>('/items', queryParameters: <String, Object?>{'q': 'x'});

    final json = registry.records.single.toJson();
    expect(json['url'], 'https://api.example.com/items?q=x');
    expect(json['statusCode'], 200);
    expect(json['method'], 'GET');
  });
}
