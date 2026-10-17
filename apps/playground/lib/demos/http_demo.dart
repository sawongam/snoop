import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snoop_http/snoop_http.dart';
import 'package:snoop_playground/demos/demo_page.dart';

final Uri _base = Uri.parse('https://fake.snoop.local');

/// An in-memory server for package:http, so the demo works offline.
MockClient fakeHttpServer() => MockClient.streaming((request, bodyStream) async {
  await bodyStream.drain<void>();
  http.StreamedResponse json(Object? value, {int status = 200}) => http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(value))),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );
  switch ((request.method, request.url.path)) {
    case ('GET', '/posts'):
      return json(<Object?>[
        <String, Object?>{'id': 1, 'title': 'First post'},
      ]);
    case ('POST', '/posts'):
      return json(<String, Object?>{'id': 2}, status: 201);
    case ('GET', '/download'):
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable(
          List<List<int>>.generate(8, (i) => List<int>.filled(4096, i)),
        ),
        200,
        headers: <String, String>{'content-type': 'application/octet-stream'},
        contentLength: 8 * 4096,
      );
    default:
      return json(<String, Object?>{'error': 'not found'}, status: 404);
  }
});

/// http: a wrapped client, top-level calls through `SnoopHttp.runZoned`, a streaming download.
class HttpDemo extends StatefulWidget {
  /// Creates the screen.
  const HttpDemo({super.key});

  @override
  State<HttpDemo> createState() => _HttpDemoState();
}

class _HttpDemoState extends State<HttpDemo> {
  final http.Client _client = SnoopHttpClient(fakeHttpServer());
  final http.Client _real = SnoopHttpClient(http.Client());
  String _status = 'Tap a button.';

  @override
  void dispose() {
    _client.close();
    _real.close();
    super.dispose();
  }

  Future<void> _run(String label, Future<String> Function() call) async {
    setState(() => _status = '$label ...');
    String result;
    try {
      result = '$label: ${await call()}';
    } on Object catch (e) {
      result = '$label: failed ($e)';
    }
    if (mounted) setState(() => _status = result);
  }

  Future<String> _topLevel() {
    // The outer zone supplies the fake; `runZoned` wraps whatever client is created inside.
    return http.runWithClient(
      () =>
          SnoopHttp.runZoned(() async => '${(await http.get(_base.resolve('/posts'))).statusCode}'),
      fakeHttpServer,
    );
  }

  Future<String> _stream() async {
    final response = await _client.send(http.Request('GET', _base.resolve('/download')));
    var bytes = 0;
    await response.stream.forEach((chunk) => bytes += chunk.length);
    return '$bytes bytes streamed';
  }

  @override
  Widget build(BuildContext context) => DemoPage(
    title: 'http',
    children: <Widget>[
      const DemoSection('SnoopHttpClient', hint: 'Wraps an in-memory client.'),
      DemoButtons(<String, VoidCallback?>{
        'GET': () =>
            _run('GET', () async => '${(await _client.get(_base.resolve('/posts'))).statusCode}'),
        'POST': () => _run(
          'POST',
          () async =>
              '${(await _client.post(_base.resolve('/posts'), body: '{"a":1}')).statusCode}',
        ),
        'Error 404': () =>
            _run('Error', () async => '${(await _client.get(_base.resolve('/nope'))).statusCode}'),
        'Streaming download': () => _run('Stream', _stream),
      }),
      const DemoSection('SnoopHttp.runZoned', hint: 'A top-level http.get(...) call.'),
      DemoButtons(<String, VoidCallback?>{'Top-level GET': () => _run('Top-level', _topLevel)}),
      const DemoSection('Real network', hint: 'Needs internet access.'),
      DemoButtons(<String, VoidCallback?>{
        'GET httpbin.org': () => _run(
          'httpbin',
          () async => '${(await _real.get(Uri.https('httpbin.org', '/get'))).statusCode}',
        ),
      }),
      DemoStatus(_status),
    ],
  );
}
