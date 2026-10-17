import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

import 'helpers/fakes.dart';

SnoopCallRecord _call(int id, {String path = '/items', int? status = 200}) =>
    SnoopCallRecord(
        id: id,
        client: 'test',
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
    final har = buildHar(<SnoopCallRecord>[_call(2, path: '/second'), _call(1, path: '/first')]);
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
    final pending = SnoopCallRecord(
      id: 2,
      client: 'test',
      method: 'GET',
      uri: Uri.parse('https://api.example.com/slow'),
      startedAt: DateTime(2026),
    );
    final entries =
        (buildHar(<SnoopCallRecord>[pending, failed])['log']! as Map)['entries']! as List;

    final failedEntry = entries.first as Map<String, Object?>;
    expect((failedEntry['response']! as Map)['status'], 0);
    expect((failedEntry['response']! as Map)['statusText'], 'connectionError');
    expect(failedEntry['_error'], 'Connection refused');
    expect(failedEntry['_snoopFault'], 'offline');
    expect((entries.last as Map)['_pending'], isTrue);
  });

  test('buildSessionExport bundles every recorder as JSON', () async {
    registerFakeAdapters();
    trackFake(FakeSource(0), name: 'CounterBloc', kind: 'bloc', increments: 1, withEvents: true);
    Snoop.network.add(_call(1));
    Snoop.logs.log('Signed in', level: SnoopLogLevel.info, source: 'AuthBloc');

    final session =
        jsonDecode(jsonEncode(buildSessionExport(now: DateTime(2026, 10, 15))))
            as Map<String, Object?>;

    expect(session['exportedAt'], startsWith('2026-10-15'));
    expect(session['network'], hasLength(1));
    expect(session['adapters'], <String, Object?>{'fake_http': 'network', 'fake_state': 'state'});
    final sources = (session['state']! as List).cast<Map<String, Object?>>();
    final counter = sources.singleWhere((b) => b['name'] == 'CounterBloc');
    expect(counter['state'], 1);
    expect(counter['kind'], 'bloc');
    expect(counter['library'], 'fake_state');
    final change = (counter['history']! as List).single as Map<String, Object?>;
    expect(change['event'], 'Incremented');
    expect(change['changes'], <String>['~ (state): 0 → 1']);
    expect((session['logs']! as List).single, containsPair('message', 'Signed in'));
    expect(session['routes'], isEmpty);
  });

  test('buildSessionExport lists disposed sources with their details', () {
    final key = FakeSource(0);
    Snoop.state.track(
      key,
      name: 'todosProvider(3)',
      kind: 'provider',
      library: 'riverpod',
      details: <String, Object?>{'argument': 3},
    );
    Snoop.state.markDisposed(key);

    final source = (buildSessionExport()['state']! as List).single as Map<String, Object?>;
    expect(source['details'], <String, Object?>{'argument': 3});
    expect(source['disposedAt'], isA<String>());
  });

  test('buildHar writes the client and the redirect target', () {
    final record = _call(1)..finalUri = Uri.parse('https://cdn.example.com/items');
    final entry =
        ((buildHar(<SnoopCallRecord>[record])['log']! as Map)['entries']! as List).single
            as Map<String, Object?>;
    expect(entry['_snoopClient'], 'test');
    expect((entry['response']! as Map)['redirectURL'], 'https://cdn.example.com/items');
  });
}
