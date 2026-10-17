import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_dio/snoop_dio.dart';

import 'helpers/fakes.dart';

void main() {
  final registry = Snoop.network;

  setUp(() {
    Snoop.reset();
    registry.maxRecords = 100;
  });

  group('replay', () {
    test('resends the call through the replay client and links it', () async {
      final sent = <RequestOptions>[];
      final dio = fakeDio();
      dio.interceptors
        ..add(SnoopDioInterceptor(enabled: true, replayClient: dio))
        ..add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              sent.add(o);
              h.next(o);
            },
          ),
        );

      await dio.post<Object?>('/items', data: <String, Object?>{'name': 'tea'});
      final original = registry.records.single;
      final replayed = await original.replay();

      expect(replayed, isNotNull);
      expect(replayed!.id, isNot(original.id));
      expect(replayed.replayOf, original.id);
      expect(replayed.statusCode, 200);
      expect(registry.count, 2);
      expect(sent.last.data, <String, Object?>{'name': 'tea'});
    });

    test('sends edits, restoring redacted header values', () async {
      final sent = <RequestOptions>[];
      final dio = fakeDio();
      dio.interceptors
        ..add(SnoopDioInterceptor(enabled: true, replayClient: dio))
        ..add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              sent.add(o);
              h.next(o);
            },
          ),
        );

      await dio.get<Object?>(
        '/items',
        options: Options(headers: <String, Object?>{'Authorization': 'Bearer secret'}),
      );
      final original = registry.records.single;
      expect(original.requestHeaders['Authorization'], SnoopHeaders.redactedValue);

      final request = original.toReplayRequest()
        ..method = 'put'
        ..uri = Uri.parse('https://other.example.com/edited?x=1')
        ..headers['x-extra'] = '1'
        ..body = <String, Object?>{'edited': true};
      final replayed = await original.replay(request);

      final options = sent.last;
      expect(options.method, 'PUT');
      expect(options.uri.toString(), 'https://other.example.com/edited?x=1');
      expect(options.headers['Authorization'], 'Bearer secret');
      expect(options.headers['x-extra'], '1');
      expect(options.data, <String, Object?>{'edited': true});
      // The new record is redacted again.
      expect(replayed!.requestHeaders['Authorization'], SnoopHeaders.redactedValue);
    });

    test('records failed replays', () async {
      final dio = fakeDio();
      dio.interceptors.add(SnoopDioInterceptor(enabled: true, replayClient: dio));
      await expectLater(dio.get<Object?>('/missing'), throwsA(isA<DioException>()));

      final replayed = await registry.records.single.replay();
      expect(replayed!.statusCode, 404);
      expect(replayed.isError, isTrue);
    });
  });

  group('network conditions', () {
    tearDown(Snoop.networkConditions.reset);

    test('delays affected calls', () async {
      final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: true));
      Snoop.networkConditions.delay = const Duration(milliseconds: 120);

      final watch = Stopwatch()..start();
      await dio.get<Object?>('/items');
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(110));
      expect(registry.records.single.statusCode, 200);
    });

    test('fails calls with an HTTP fault that still reaches error interceptors', () async {
      var errorsSeen = 0;
      final dio = fakeDio()
        ..interceptors.add(SnoopDioInterceptor(enabled: true))
        ..interceptors.add(
          InterceptorsWrapper(
            onError: (e, h) {
              errorsSeen++;
              h.next(e);
            },
          ),
        );
      Snoop.networkConditions
        ..failureRate = 1
        ..fault = SnoopFault.unauthorized;

      final error = await dio
          .get<Object?>('/items')
          .then<DioException?>((_) => null, onError: (Object e) => e as DioException);

      expect(error?.type, DioExceptionType.badResponse);
      expect(error?.response?.statusCode, 401);
      expect(errorsSeen, 1);
      final r = registry.records.single;
      expect(r.statusCode, 401);
      expect(r.injectedFault, SnoopFault.unauthorized);
      expect(r.completed, isTrue);
      expect(r.isError, isTrue);
    });

    test('fails calls with a network fault', () async {
      final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: true));
      Snoop.networkConditions
        ..failureRate = 1
        ..fault = SnoopFault.offline;

      await expectLater(
        dio.get<Object?>('/items'),
        throwsA(
          isA<DioException>().having((e) => e.type, 'type', DioExceptionType.connectionError),
        ),
      );
      final r = registry.records.single;
      expect(r.statusCode, isNull);
      expect(r.errorType, 'connectionError');
      expect(r.injectedFault, SnoopFault.offline);
    });

    test('only affects URLs matching the filter', () async {
      final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: true));
      Snoop.networkConditions
        ..failureRate = 1
        ..urlFilter = '/ORDERS';

      await dio.get<Object?>('/items');
      await expectLater(dio.get<Object?>('/orders/1'), throwsA(isA<DioException>()));

      expect(registry.records.map((r) => r.statusCode), <int?>[500, 200]);
    });

    test('rolls failures at the configured rate', () {
      Snoop.networkConditions
        ..random = Random(1)
        ..failureRate = 0.3;
      final failures = List<bool>.generate(
        1000,
        (_) => Snoop.networkConditions.rollFailure(),
      ).where((f) => f).length;
      expect(failures, inInclusiveRange(240, 360));
    });

    test('does nothing through a disabled interceptor', () async {
      final dio = fakeDio()..interceptors.add(SnoopDioInterceptor(enabled: false));
      Snoop.networkConditions.failureRate = 1;
      final response = await dio.get<Object?>('/items');
      expect(response.statusCode, 200);
    });

    test('summary describes what is simulated', () {
      expect(Snoop.networkConditions.summary, isNull);
      Snoop.networkConditions
        ..delay = const Duration(seconds: 2)
        ..failureRate = 0.25
        ..fault = SnoopFault.serverError
        ..urlFilter = '/orders';
      expect(Snoop.networkConditions.summary, '+2s  ·  25% fail with 500  ·  /orders');
    });
  });
}
