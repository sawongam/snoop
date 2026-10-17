import 'dart:convert';

import 'package:chopper/chopper.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snoop_chopper/snoop_chopper.dart';
import 'package:snoop_playground/demos/demo_page.dart';

/// What `chopper_generator` would write for a small `@ChopperApi` service, by hand.
final class PostsService extends ChopperService {
  /// Creates the service, optionally bound to [client] already.
  PostsService([ChopperClient? client]) {
    if (client != null) this.client = client;
  }

  @override
  Type get definitionType => PostsService;

  /// `GET /posts`.
  Future<Response<Object?>> list() {
    final request = Request('GET', Uri.parse('/posts'), client.baseUrl);
    return client.send<Object?, Object?>(request);
  }

  /// `GET /posts/{id}`.
  Future<Response<Object?>> byId(int id) {
    final request = Request('GET', Uri.parse('/posts/$id'), client.baseUrl);
    return client.send<Object?, Object?>(request);
  }

  /// `POST /posts` with a JSON body.
  Future<Response<Object?>> create(Map<String, Object?> body) {
    final request = Request('POST', Uri.parse('/posts'), client.baseUrl, body: body);
    return client.send<Object?, Object?>(request);
  }
}

/// An in-memory server for the Chopper client's `http.Client`.
MockClient fakeChopperServer() => MockClient((request) async {
  http.Response json(Object? value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );
  switch ((request.method, request.url.path)) {
    case ('GET', '/posts'):
      return json(<Object?>[
        <String, Object?>{'id': 1, 'title': 'First post'},
        <String, Object?>{'id': 2, 'title': 'Second post'},
      ]);
    case ('GET', '/posts/1'):
      return json(<String, Object?>{'id': 1, 'title': 'First post'});
    case ('POST', '/posts'):
      return json(<String, Object?>{'id': 3}, 201);
    default:
      return json(<String, Object?>{'error': 'not found'}, 404);
  }
});

/// Chopper: a hand-written service over an in-memory client, plus one real call.
class ChopperDemo extends StatefulWidget {
  /// Creates the screen.
  const ChopperDemo({super.key});

  @override
  State<ChopperDemo> createState() => _ChopperDemoState();
}

class _ChopperDemoState extends State<ChopperDemo> {
  late final ChopperClient _fake = _build(fakeChopperServer(), 'https://fake.snoop.local');
  late final ChopperClient _real = _build(http.Client(), 'https://httpbin.org');
  String _status = 'Tap a button.';

  ChopperClient _build(http.Client inner, String baseUrl) {
    late final ChopperClient client;
    client = ChopperClient(
      client: inner,
      baseUrl: Uri.parse(baseUrl),
      services: <ChopperService>[PostsService()],
      converter: const JsonConverter(),
      errorConverter: const JsonConverter(),
      // Last, so the headers it records are the ones the other interceptors set.
      interceptors: <Interceptor>[SnoopChopperInterceptor(replayClient: () => client)],
    );
    return client;
  }

  @override
  void dispose() {
    _fake.dispose();
    _real.dispose();
    super.dispose();
  }

  Future<void> _run(String label, Future<Response<Object?>> Function() call) async {
    setState(() => _status = '$label ...');
    String result;
    try {
      result = '$label: ${(await call()).statusCode}';
    } on Object catch (e) {
      result = '$label: failed ($e)';
    }
    if (mounted) setState(() => _status = result);
  }

  @override
  Widget build(BuildContext context) {
    final posts = _fake.getService<PostsService>();
    return DemoPage(
      title: 'Chopper',
      children: <Widget>[
        const DemoSection('Hand-written service', hint: 'Over an in-memory http client.'),
        DemoButtons(<String, VoidCallback?>{
          'List': () => _run('List', posts.list),
          'Get 1': () => _run('Get 1', () => posts.byId(1)),
          'Create': () => _run('Create', () => posts.create(<String, Object?>{'title': 'New'})),
          'Error 404': () => _run('Error', () => posts.byId(404)),
        }),
        const DemoSection('Real network', hint: 'Needs internet access.'),
        DemoButtons(<String, VoidCallback?>{
          'GET httpbin.org': () =>
              _run('httpbin', () => _real.get<Object?, Object?>(Uri.parse('/get'))),
        }),
        DemoStatus(_status),
      ],
    );
  }
}
