import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

DioCallRecord _call({
  required int id,
  String method = 'GET',
  String path = '/dishes',
  int? status = 200,
  int? ms = 100,
  String? error,
}) {
  final record = DioCallRecord(
    id: id,
    method: method,
    uri: Uri.parse('https://api.example.com$path'),
    startedAt: DateTime.utc(2026),
  )..error = error;
  if (ms != null) {
    record
      ..statusCode = status
      ..duration = Duration(milliseconds: ms)
      ..completed = true;
  }
  return record;
}

void main() {
  group('DioCallStats', () {
    test('is all zeroes and nulls over nothing', () {
      final stats = DioCallStats.of(const []);

      expect(stats.total, 0);
      expect(stats.errorRate, 0);
      expect(stats.medianMs, isNull);
      expect(stats.p95Ms, isNull);
      expect(stats.slowestMs, isNull);
    });

    test('counts failures by status and by transport error', () {
      final stats = DioCallStats.of([
        _call(id: 1),
        _call(id: 2, status: 404),
        _call(id: 3, status: null, ms: null, error: 'connection refused'),
      ]);

      expect(stats.total, 3);
      expect(stats.errors, 2);
      expect(stats.pending, 1);
      expect(stats.errorRate, closeTo(2 / 3, 0.001));
    });

    test('a single sample is its own median, p95 and slowest', () {
      final stats = DioCallStats.of([_call(id: 1, ms: 240)]);

      expect(stats.medianMs, 240);
      expect(stats.p95Ms, 240);
      expect(stats.slowestMs, 240);
    });

    test('p95 is nearest-rank, so one outlier does not become the median', () {
      final stats = DioCallStats.of([
        for (var i = 1; i <= 19; i++) _call(id: i, ms: 100),
        _call(id: 20, ms: 4000),
      ]);

      expect(stats.medianMs, 100);
      expect(stats.p95Ms, 100);
      expect(stats.slowestMs, 4000);
    });

    test('readableStatus is plain language, not percentiles', () {
      expect(DioCallStats.of(const []).readableStatus, isNull);

      expect(DioCallStats.of([_call(id: 1), _call(id: 2)]).readableStatus, 'All OK');

      expect(DioCallStats.of([_call(id: 1), _call(id: 2, status: 500)]).readableStatus, '1 OK');

      expect(
        DioCallStats.of([_call(id: 1, status: 500), _call(id: 2, status: 404)]).readableStatus,
        isNull,
      );
    });

    test('endpointStatus reads as ok, failed or in flight', () {
      expect(DioCallStats.of([_call(id: 1)]).endpointStatus, 'OK');

      final failed = DioCallStats.of([_call(id: 1), _call(id: 2, status: 500)]);
      expect(failed.endpointStatus, '1 failed');

      final pending = DioCallStats.of([_call(id: 1, ms: null)]);
      expect(pending.endpointStatus, '1 in flight');
    });

    test('reports response size only when a content-length was seen', () {
      final none = DioCallStats.of([_call(id: 1)]);
      final sized = DioCallStats.of([
        _call(id: 1)..responseBytes = 2048,
        _call(id: 2)..responseBytes = 1024,
      ]);

      expect(none.readableBytes, isNull);
      expect(sized.bytes, 3072);
      expect(sized.readableBytes, '3 kB');
    });

    test('a pending call is counted but does not enter the percentiles', () {
      final stats = DioCallStats.of([_call(id: 1, ms: 100), _call(id: 2, ms: null)]);

      expect(stats.total, 2);
      expect(stats.pending, 1);
      expect(stats.medianMs, 100);
    });
  });

  group('DioEndpointStats', () {
    test('groups by method and path, slowest p95 first', () {
      final rows = DioEndpointStats.group([
        _call(id: 1, path: '/dishes', ms: 50),
        _call(id: 2, path: '/dishes', ms: 70),
        _call(id: 3, path: '/orders', ms: 900),
        _call(id: 4, method: 'POST', path: '/dishes', ms: 300),
      ]);

      expect(rows.map((r) => r.endpoint), ['GET /orders', 'POST /dishes', 'GET /dishes']);
      expect(rows.last.stats.total, 2);
    });

    test('a query string does not split one endpoint into two rows', () {
      final rows = DioEndpointStats.group([
        DioCallRecord(
          id: 1,
          method: 'GET',
          uri: Uri.parse('https://api.example.com/dishes?page=1'),
          startedAt: DateTime.utc(2026),
        ),
        DioCallRecord(
          id: 2,
          method: 'GET',
          uri: Uri.parse('https://api.example.com/dishes?page=2'),
          startedAt: DateTime.utc(2026),
        ),
      ]);

      expect(rows.single.endpoint, 'GET /dishes');
      expect(rows.single.stats.total, 2);
    });
  });
}
