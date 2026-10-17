import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

void main() {
  setUp(() {
    Snoop.reset();
    Snoop.network.maxBodyChars = 256 * 1024;
  });

  group('SnoopBody.normalize', () {
    test('passes plain values through', () {
      expect(SnoopBody.normalize(null).body, isNull);
      expect(SnoopBody.normalize(3).body, 3);
      expect(SnoopBody.normalize(<String, Object?>{'a': 1}).body, <String, Object?>{'a': 1});
      expect(SnoopBody.normalize(<int>[1, 2], contentType: 'application/json').body, <int>[1, 2]);
    });

    test('decodes UTF-8 text bytes', () {
      final r = SnoopBody.normalize(utf8.encode('héllo'), contentType: 'text/plain');
      expect(r.body, 'héllo');
      expect(r.truncated, isFalse);
    });

    test('decodes JSON bytes', () {
      final bytes = Uint8List.fromList(utf8.encode('{"id": 1}'));
      expect(SnoopBody.normalize(bytes, contentType: 'application/json').body, <String, Object?>{
        'id': 1,
      });
      expect(SnoopBody.normalize(bytes).body, <String, Object?>{'id': 1}); // Sniffed.
    });

    test('summarizes binary bytes', () {
      final png = Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 0, 0, 0xff, 0xfe]);
      expect(SnoopBody.normalize(png).body, '<binary, 8 B>');
      expect(
        SnoopBody.normalize(utf8.encode('looks like text'), contentType: 'image/png').body,
        startsWith('<binary'),
      );
    });

    test('cuts long strings and bytes at maxBodyChars', () {
      Snoop.network.maxBodyChars = 4;
      final text = SnoopBody.normalize('abcdefgh');
      expect(text.body, 'abcd');
      expect(text.truncated, isTrue);
      // A cut through a multi-byte character still decodes.
      final bytes = SnoopBody.normalize(utf8.encode('abcé'), contentType: 'text/plain');
      expect(bytes.body, 'abc');
      expect(bytes.truncated, isTrue);
    });

    test('streams are not read', () {
      expect(SnoopBody.normalize(const Stream<List<int>>.empty()).body, '<stream>');
    });
  });

  group('SnoopHeaders', () {
    test('flattens list values and redacts case-insensitively', () {
      final flat = SnoopHeaders.flatten(<String, Object?>{
        'Accept': <String>['a', 'b'],
        'Authorization': 'Bearer secret',
        'x-count': 3,
      }, SnoopHeaders.defaultRedacted);
      expect(flat, <String, String>{
        'Accept': 'a, b',
        'Authorization': SnoopHeaders.redactedValue,
        'x-count': '3',
      });
    });

    test('unredact restores what was sent', () {
      final restored = SnoopHeaders.unredact(
        <String, String>{'authorization': SnoopHeaders.redactedValue, 'x-new': 'v'},
        <String, Object?>{'Authorization': 'Bearer secret'},
      );
      expect(restored, <String, String>{'authorization': 'Bearer secret', 'x-new': 'v'});
    });
  });

  group('SnoopNetworkConditions.simulate', () {
    tearDown(Snoop.networkConditions.reset);

    test('returns null when nothing is simulated or the URL is filtered out', () {
      final uri = Uri.parse('https://api.example.com/orders');
      expect(Snoop.networkConditions.simulate(uri), isNull);
      Snoop.networkConditions
        ..delay = const Duration(seconds: 1)
        ..urlFilter = '/users';
      expect(Snoop.networkConditions.simulate(uri), isNull);
    });

    test('rolls the failure once per call', () {
      Snoop.networkConditions
        ..random = Random(7)
        ..failureRate = 0.5
        ..fault = SnoopFault.timeout;
      final expected = Random(7);
      final uri = Uri.parse('https://api.example.com/orders');
      for (var i = 0; i < 20; i++) {
        final fails = expected.nextDouble() < 0.5;
        final simulation = Snoop.networkConditions.simulate(uri);
        expect(simulation?.fault, fails ? SnoopFault.timeout : null);
      }
    });

    test('a delay alone sends the call late', () {
      Snoop.networkConditions.delay = const Duration(milliseconds: 300);
      final simulation = Snoop.networkConditions.simulate(Uri.parse('https://x.dev'))!;
      expect(simulation.delay, const Duration(milliseconds: 300));
      expect(simulation.fault, isNull);
    });
  });

  group('buildCurl', () {
    test('quotes, skips redacted headers and sends the body as binary', () {
      final record = SnoopCallRecord(
        id: 1,
        client: 'test',
        method: 'POST',
        uri: Uri.parse("https://api.example.com/it's"),
        startedAt: DateTime(2026),
        requestBody: <String, Object?>{'name': "o'brien"},
        requestHeaders: <String, String>{
          'content-type': 'application/json',
          'authorization': SnoopHeaders.redactedValue,
        },
      );
      final curl = buildCurl(record);
      expect(curl, startsWith('# redacted: authorization\ncurl -X POST'));
      expect(curl, contains(r"'https://api.example.com/it'\''s'"));
      expect(curl, isNot(contains(SnoopHeaders.redactedValue)));
      expect(curl, contains(r"""--data-binary '{"name":"o'\''brien"}'"""));
    });
  });

  test('cancelled calls are not errors', () {
    final record =
        SnoopCallRecord(
            id: 1,
            client: 'test',
            method: 'GET',
            uri: Uri.parse('https://x.dev'),
            startedAt: DateTime(2026),
          )
          ..cancelled = true
          ..error = 'cancelled'
          ..completed = true;
    Snoop.network.add(record);
    expect(record.isError, isFalse);
    expect(Snoop.network.errorCount, 0);
    expect(SnoopCallStats.of(<SnoopCallRecord>[record]).cancelled, 1);
  });
}
