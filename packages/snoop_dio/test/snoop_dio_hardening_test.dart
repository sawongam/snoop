import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_dio/snoop_dio.dart';

import 'helpers/fakes.dart';

/// Never answers; the call can only end by being cancelled.
class _HangingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => Completer<ResponseBody>().future;

  @override
  void close({bool force = false}) {}
}

void main() {
  final registry = Snoop.network;

  setUp(() {
    Snoop.reset();
    registry.maxRecords = 100;
    registry.maxBodyChars = 256 * 1024;
  });

  tearDown(Snoop.networkConditions.reset);

  group('registration', () {
    test('registers the dio network adapter when enabled', () {
      SnoopDioInterceptor(enabled: true);
      expect(SnoopAdapters.all['dio'], SnoopAdapterKind.network);
    });

    test('does not register when disabled', () {
      SnoopDioInterceptor(enabled: false);
      expect(SnoopAdapters.ids, isEmpty);
    });
  });

  group('bodies', () {
    test('JSON request and response', () async {
      final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: true));
      await dio.post<Object?>('/items', data: <String, Object?>{'a': 1});
      final r = registry.records.single;
      expect(r.requestBody, <String, Object?>{'a': 1});
      expect(r.responseBody, isA<Map<String, Object?>>());
    });

    test('text request and response, with request bytes', () async {
      final dio = dioOn(BytesAdapter(utf8.encode('héllo'), contentType: 'text/plain'))
        ..interceptors.add(SnoopDioInterceptor(enabled: true));
      await dio.post<String>(
        '/t',
        data: 'héllo',
        options: Options(contentType: 'text/plain', responseType: ResponseType.plain),
      );
      final r = registry.records.single;
      expect(r.requestBody, 'héllo');
      expect(r.requestBytes, 6);
      expect(r.responseBody, 'héllo');
    });

    test('request bytes come from byte lists and are null for maps', () async {
      final dio = dioOn(BytesAdapter(<int>[]))
        ..interceptors.add(SnoopDioInterceptor(enabled: true));
      await dio.post<Object?>('/b', data: Uint8List.fromList(<int>[1, 2, 3]));
      await dio.post<Object?>('/m', data: <String, Object?>{'a': 1});
      expect(registry.records.last.requestBytes, 3);
      expect(registry.records.first.requestBytes, isNull);
    });

    test('bytes response with a JSON content type is decoded', () async {
      final dio = dioOn(BytesAdapter(utf8.encode('{"ok":true}'), contentType: 'application/json'))
        ..interceptors.add(SnoopDioInterceptor(enabled: true));
      await dio.get<List<int>>('/j', options: Options(responseType: ResponseType.bytes));
      expect(registry.records.single.responseBody, <String, Object?>{'ok': true});
    });

    test('binary response is recorded as a size label', () async {
      final dio = dioOn(BytesAdapter(List<int>.filled(2048, 7), contentType: 'image/png'))
        ..interceptors.add(SnoopDioInterceptor(enabled: true));
      await dio.get<List<int>>('/img', options: Options(responseType: ResponseType.bytes));
      expect(registry.records.single.responseBody, '<binary, 2.0 kB>');
    });

    test('stream response is never read', () async {
      final adapter = BytesAdapter(utf8.encode('payload'), contentType: 'text/plain');
      final dio = dioOn(adapter)..interceptors.add(SnoopDioInterceptor(enabled: true));
      final response = await dio.get<ResponseBody>(
        '/s',
        options: Options(responseType: ResponseType.stream),
      );
      expect(registry.records.single.responseBody, '<stream>');
      // The app can still read the whole stream.
      final read = await response.data!.stream.expand((c) => c).toList();
      expect(utf8.decode(read), 'payload');
    });

    test('stream request body is recorded as <stream> and not replayable', () async {
      final dio = dioOn(BytesAdapter(<int>[]))
        ..interceptors.add(SnoopDioInterceptor(enabled: true));
      final data = Stream<List<int>>.value(<int>[1, 2, 3]);
      await dio.post<Object?>(
        '/up',
        data: data,
        options: Options(headers: <String, Object?>{Headers.contentLengthHeader: 3}),
      );
      final r = registry.records.single;
      expect(r.requestBody, '<stream>');
      expect(r.canReplay, isFalse);
      expect(await r.replay(), isNull);
    });

    test('FormData lists fields and file lengths', () async {
      final dio = dioOn(BytesAdapter(<int>[]))
        ..interceptors.add(SnoopDioInterceptor(enabled: true));
      await dio.post<Object?>(
        '/form',
        data: FormData.fromMap(<String, Object?>{
          'a': '1',
          'file': MultipartFile.fromBytes(List<int>.filled(2048, 0), filename: 'x.bin'),
        }),
      );
      expect(registry.records.single.requestBody, <String, Object?>{
        'fields': <String, String>{'a': '1'},
        'files': <String>['file: x.bin (2.0 kB)'],
      });
    });

    test('bodies over maxBodyChars are truncated and flagged', () async {
      registry.maxBodyChars = 10;
      final dio = dioOn(BytesAdapter(utf8.encode('x' * 50), contentType: 'text/plain'))
        ..interceptors.add(SnoopDioInterceptor(enabled: true));
      await dio.post<String>(
        '/big',
        data: 'y' * 50,
        options: Options(contentType: 'text/plain', responseType: ResponseType.plain),
      );
      final r = registry.records.single;
      expect(r.requestBody, 'y' * 10);
      expect(r.requestTruncated, isTrue);
      expect(r.responseBody, 'x' * 10);
      expect(r.responseTruncated, isTrue);
    });
  });

  group('lifecycle', () {
    test('cancel is recorded as cancelled, not as an error', () async {
      final dio = dioOn(_HangingAdapter())..interceptors.add(SnoopDioInterceptor(enabled: true));
      final token = CancelToken();
      final future = dio.get<Object?>('/slow', cancelToken: token);
      final settled = expectLater(
        future,
        throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      token.cancel('stop');
      await settled;

      final r = registry.records.single;
      expect(r.cancelled, isTrue);
      expect(r.error, isNull);
      expect(r.isError, isFalse);
      expect(r.completed, isTrue);
      expect(registry.errorCount, 0);
      expect(registry.cancelledCount, 1);
    });

    test('a retry makes a second record linked to the first', () async {
      var attempts = 0;
      final dio = fakeDio();
      dio.interceptors
        ..add(SnoopDioInterceptor(enabled: true))
        ..add(
          InterceptorsWrapper(
            onError: (e, h) async {
              if (attempts++ > 0) return h.next(e);
              try {
                h.resolve(await dio.fetch<Object?>(e.requestOptions));
              } on DioException catch (error) {
                h.next(error);
              }
            },
          ),
        );

      await dio.get<Object?>('/missing').then<Object?>((_) => null, onError: (Object _) => null);

      expect(registry.count, 2);
      final first = registry.records.last;
      final second = registry.records.first;
      expect(first.retryOf, isNull);
      expect(first.completed, isTrue);
      expect(first.isPending, isFalse);
      expect(second.retryOf, first.id);
    });

    test('a retry of a pending call supersedes it', () async {
      final dio = dioOn(_HangingAdapter())..interceptors.add(SnoopDioInterceptor(enabled: true));
      // A retry interceptor re-fetching the same options while the first
      // attempt never completed.
      final options = RequestOptions(path: '/x', baseUrl: 'https://api.example.com');
      unawaited(dio.fetch<Object?>(options).then<void>((_) {}, onError: (Object _) {}));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final first = registry.records.single;
      expect(first.isPending, isTrue);

      unawaited(dio.fetch<Object?>(options).then<void>((_) {}, onError: (Object _) {}));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(first.completed, isTrue);
      expect(first.errorType, 'superseded');
      expect(registry.records.first.retryOf, first.id);
    });

    // Dio never runs response interceptors after an error interceptor
    // resolves (ErrorInterceptorHandler.resolve has no call-following
    // variant), so this drives onError and onResponse by hand.
    test('a response after a recorded error ends the record as a success', () async {
      final interceptor = SnoopDioInterceptor(enabled: true);
      final options = RequestOptions(path: '/missing', baseUrl: 'https://api.example.com');
      interceptor.onRequest(options, RequestInterceptorHandler());
      final response = Response<Object?>(requestOptions: options, statusCode: 200, data: 'cached');
      final errorHandler = ErrorInterceptorHandler();
      // ignore: invalid_use_of_protected_member
      unawaited(errorHandler.future.then<void>((_) {}, onError: (Object _) {}));
      interceptor.onError(
        DioException.badResponse(statusCode: 404, requestOptions: options, response: response),
        errorHandler,
      );
      final r = registry.records.single;
      expect(r.isError, isTrue);

      interceptor.onResponse(response, ResponseInterceptorHandler());

      expect(r.statusCode, 200);
      expect(r.error, isNull);
      expect(r.isError, isFalse);
      expect(r.completed, isTrue);
      expect(r.responseBody, 'cached');
      expect(r.toJson()['recoveredFrom'], isNotNull);
    });

    test('two Snoop interceptors on one Dio record once', () async {
      final dio = fakeDio()
        ..interceptors.add(SnoopDioInterceptor(enabled: true))
        ..interceptors.add(SnoopDioInterceptor(enabled: true));
      Snoop.networkConditions.delay = const Duration(milliseconds: 5);

      await dio.get<Object?>('/items');
      await expectLater(dio.get<Object?>('/missing'), throwsA(isA<DioException>()));

      expect(registry.count, 2);
      expect(registry.records.every((r) => r.completed), isTrue);
      expect(registry.records.first.statusCode, 404);
    });

    test('a redirect records the final URL', () async {
      final target = Uri.parse('https://cdn.example.com/final');
      final dio = dioOn(BytesAdapter(utf8.encode('{}'), redirectTo: target))
        ..interceptors.add(SnoopDioInterceptor(enabled: true));
      await dio.get<Object?>('/start');
      final r = registry.records.single;
      expect(r.finalUri, target);
      expect(r.toJson()['finalUrl'], target.toString());
    });

    test('no redirect leaves finalUri empty', () async {
      final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: true));
      await dio.get<Object?>('/items');
      expect(registry.records.single.finalUri, isNull);
    });
  });

  group('switches', () {
    test('shouldRecord false records and simulates nothing', () async {
      final dio = fakeDio()
        ..interceptors.add(SnoopDioInterceptor(enabled: true, shouldRecord: (_) => false));
      Snoop.networkConditions.failureRate = 1;
      final response = await dio.get<Object?>('/items');
      expect(response.statusCode, 200);
      expect(registry.count, 0);
    });

    test('a throwing shouldRecord does not break the call', () async {
      final dio = fakeDio()
        ..interceptors.add(SnoopDioInterceptor(enabled: true, shouldRecord: (_) => throw 'boom'));
      final response = await dio.get<Object?>('/items');
      expect(response.statusCode, 200);
    });

    test('enabled false passes straight through', () async {
      final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: false));
      Snoop.networkConditions
        ..delay = const Duration(seconds: 5)
        ..failureRate = 1;
      final watch = Stopwatch()..start();
      final response = await dio.get<Object?>('/items');
      expect(response.statusCode, 200);
      expect(watch.elapsedMilliseconds, lessThan(2000));
      expect(registry.count, 0);
    });

    test('a simulated 401 reaches the app refresh interceptor', () async {
      var refreshed = 0;
      final dio = fakeDio();
      dio.interceptors
        ..add(SnoopDioInterceptor(enabled: true))
        ..add(
          InterceptorsWrapper(
            onError: (e, h) async {
              if (e.response?.statusCode != 401) return h.next(e);
              refreshed++;
              Snoop.networkConditions.reset();
              h.resolve(await dio.fetch<Object?>(e.requestOptions));
            },
          ),
        );
      Snoop.networkConditions
        ..failureRate = 1
        ..fault = SnoopFault.unauthorized;

      final response = await dio.get<Object?>('/items');

      expect(refreshed, 1);
      expect(response.statusCode, 200);
      expect(registry.records.last.injectedFault, SnoopFault.unauthorized);
      expect(registry.records.first.retryOf, registry.records.last.id);
    });
  });

  group('replay', () {
    test('a FormData call is cloned, a finalized form would fail', () async {
      final sent = <Object?>[];
      final dio = dioOn(BytesAdapter(<int>[]));
      dio.interceptors
        ..add(SnoopDioInterceptor(enabled: true, replayClient: dio))
        ..add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              sent.add(o.data);
              h.next(o);
            },
          ),
        );
      final form = FormData.fromMap(<String, Object?>{
        'a': '1',
        'f': MultipartFile.fromBytes(<int>[1, 2], filename: 'f.bin'),
      });
      await dio.post<Object?>('/form', data: form);

      final replayed = await registry.records.single.replay();

      expect(replayed, isNotNull);
      expect(replayed!.isError, isFalse);
      expect(sent.last, isA<FormData>());
      expect(identical(sent.last, form), isFalse);
    });
  });

  testWidgets('the overlay shows a recorded dio call', (tester) async {
    final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: true));
    await tester.runAsync(() => dio.get<Object?>('/items'));

    await tester.pumpWidget(
      const MaterialApp(
        home: SnoopOverlay(child: Scaffold(body: SizedBox())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final context = tester.element(find.byType(Scaffold));
    SnoopOverlay.open(context, tab: 'network');
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('/items'), findsWidgets);
  });
}
