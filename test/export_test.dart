import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

import 'helpers/fakes.dart';

DioCallRecord _call(int id, {String path = '/items', int? status = 200}) =>
    DioCallRecord(
        id: id,
        method: 'POST',
        uri: Uri.parse('https://api.example.com$path?q=1&q=2'),
        startedAt: DateTime.utc(2026, 10, 15, 12, 0, id),
        requestBody: <String, Object?>{'name': 'tea'},
        requestHeaders: <String, String>{'content-type': 'application/json'},
      )
      ..statusCode = status
      ..completed = true
      ..duration = const Duration(milliseconds: 80)
      ..responseHeaders = <String, String>{'content-type': 'application/json; charset=utf-8'}
      ..responseBody = <String, Object?>{'ok': true};

void main() {
  setUp(Snoop.reset);

  test('buildHar writes a HAR 1.2 log, oldest call first', () {
    final har = buildHar(<DioCallRecord>[_call(2, path: '/second'), _call(1, path: '/first')]);
    // Must survive a JSON round trip.
    final log =
        (jsonDecode(jsonEncode(har)) as Map<String, Object?>)['log']! as Map<String, Object?>;

    expect(log['version'], '1.2');
    expect((log['creator']! as Map<String, Object?>)['name'], 'snoop');
    final entries = (log['entries']! as List<Object?>).cast<Map<String, Object?>>();
    expect(entries, hasLength(2));
    final first = entries.first;
    final request = first['request']! as Map<String, Object?>;
    final response = first['response']! as Map<String, Object?>;
    expect(request['url'], 'https://api.example.com/first?q=1&q=2');
    expect(request['method'], 'POST');
    expect(request['queryString'], <Object?>[
      <String, Object?>{'name': 'q', 'value': '1'},
      <String, Object?>{'name': 'q', 'value': '2'},
    ]);
    expect(request['postData'], <String, Object?>{
      'mimeType': 'application/json',
      'text': '{"name":"tea"}',
    });
    expect(response['status'], 200);
    expect((response['content']! as Map<String, Object?>)['text'], '{"ok":true}');
    expect(first['time'], 80);
    expect(first['startedDateTime'], '2026-10-15T12:00:01.000Z');
  });

  test('buildHar marks failures, pending calls and simulated faults', () {
    final failed = _call(1, status: null)
      ..error = 'Connection refused'
      ..errorType = 'connectionError'
      ..injectedFault = SnoopFault.offline;
    final pending = DioCallRecord(
      id: 2,
      method: 'GET',
      uri: Uri.parse('https://api.example.com/slow'),
      startedAt: DateTime(2026),
    );
    final entries = (buildHar(<DioCallRecord>[pending, failed])['log']! as Map)['entries']! as List;

    final failedEntry = entries.first as Map<String, Object?>;
    expect((failedEntry['response']! as Map)['status'], 0);
    expect((failedEntry['response']! as Map)['statusText'], 'connectionError');
    expect(failedEntry['_error'], 'Connection refused');
    expect(failedEntry['_snoopFault'], 'offline');
    expect((entries.last as Map)['_pending'], isTrue);
  });

  test('buildSessionExport bundles every recorder as JSON', () async {
    Bloc.observer = SnoopBlocObserver(enabled: true, logErrors: false);
    final bloc = CounterBloc()..add(Incremented());
    await Future<void>.delayed(Duration.zero);
    Snoop.dio.add(_call(1));
    Snoop.logs.log('Signed in', level: SnoopLogLevel.info, source: 'AuthBloc');

    final session =
        jsonDecode(jsonEncode(buildSessionExport(now: DateTime(2026, 10, 15))))
            as Map<String, Object?>;

    expect(session['exportedAt'], startsWith('2026-10-15'));
    expect(session['dio'], hasLength(1));
    final blocs = (session['bloc']! as List).cast<Map<String, Object?>>();
    final counter = blocs.singleWhere((b) => b['name'] == 'CounterBloc');
    expect(counter['state'], 1);
    final change = (counter['history']! as List).single as Map<String, Object?>;
    expect(change['event'], 'Incremented');
    expect(change['changes'], <String>['~ (state): 0 → 1']);
    expect((session['logs']! as List).single, containsPair('message', 'Signed in'));
    expect(session['routes'], isEmpty);

    await bloc.close();
  });
}
