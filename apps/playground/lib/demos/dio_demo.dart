import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:snoop_dio/snoop_dio.dart';
import 'package:snoop_playground/demos/demo_page.dart';

/// A Dio adapter that answers from memory, so the demo works offline.
///
/// `/posts` (GET, POST), `/upload`, `/fail` (500), `/slow` (honours cancel) and `/flaky`
/// (fails on the first call, then works).
class FakeDioAdapter implements HttpClientAdapter {
  int _flakyCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    var sent = 0;
    final body = StringBuffer();
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        sent += chunk.length;
        body.write(utf8.decode(chunk, allowMalformed: true));
      }
    }
    switch ((options.method, options.uri.path)) {
      case ('GET', '/posts'):
        return _json(<Object?>[
          <String, Object?>{'id': 1, 'title': 'First post'},
          <String, Object?>{'id': 2, 'title': 'Second post'},
        ]);
      case ('POST', '/posts'):
        return _json(<String, Object?>{'id': 3, 'echo': body.toString()}, status: 201);
      case ('POST', '/upload'):
        return _json(<String, Object?>{'received': sent});
      case ('GET', '/slow'):
        await _delay(const Duration(seconds: 5), options, cancelFuture);
        return _json(<String, Object?>{'slow': true});
      case ('GET', '/flaky'):
        return _flakyCalls++ == 0
            ? _json(<String, Object?>{'error': 'try again'}, status: 503)
            : _json(<String, Object?>{'attempt': _flakyCalls});
      case ('GET', '/fail'):
        return _json(<String, Object?>{'error': 'simulated failure'}, status: 500);
      default:
        return _json(<String, Object?>{'error': 'not found'}, status: 404);
    }
  }

  ResponseBody _json(Object? value, {int status = 200}) => ResponseBody.fromString(
    jsonEncode(value),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  Future<void> _delay(Duration duration, RequestOptions options, Future<void>? cancel) {
    final done = Completer<void>();
    final timer = Timer(duration, () {
      if (!done.isCompleted) done.complete();
    });
    unawaited(
      cancel?.then((_) {
        timer.cancel();
        if (!done.isCompleted) {
          done.completeError(DioException.requestCancelled(requestOptions: options, reason: 'x'));
        }
      }),
    );
    return done.future;
  }

  @override
  void close({bool force = false}) {}
}

/// Dio: GET, POST, upload, error, cancel and retry against a fake adapter, plus one real call.
class DioDemo extends StatefulWidget {
  /// Creates the screen.
  const DioDemo({super.key});

  @override
  State<DioDemo> createState() => _DioDemoState();
}

class _DioDemoState extends State<DioDemo> {
  late final Dio _dio = _build(FakeDioAdapter());
  late final Dio _real = _build(null);
  String _status = 'Tap a button.';

  Dio _build(HttpClientAdapter? adapter) {
    final dio = Dio(
      BaseOptions(
        baseUrl: adapter == null ? 'https://httpbin.org' : 'https://fake.snoop.local',
        // Redacted in the Network tab by default.
        headers: <String, Object?>{'Authorization': 'Bearer demo-secret-token'},
      ),
    );
    if (adapter != null) dio.httpClientAdapter = adapter;
    // Inserted first so its onError runs before any interceptor that swallows errors.
    dio.interceptors.insert(0, SnoopDioInterceptor(replayClient: dio));
    return dio;
  }

  Future<void> _run(String label, Future<Response<Object?>> Function() call) async {
    setState(() => _status = '$label ...');
    String result;
    try {
      final response = await call();
      result = '$label: ${response.statusCode}';
    } on DioException catch (e) {
      result = '$label: ${CancelToken.isCancel(e) ? 'cancelled' : 'failed (${e.type.name})'}';
    }
    if (mounted) setState(() => _status = result);
  }

  Future<void> _cancel() async {
    final token = CancelToken();
    final call = _run('Cancel', () => _dio.get<Object?>('/slow', cancelToken: token));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    token.cancel('cancelled from the demo');
    await call;
  }

  Future<void> _retry() async {
    await _run('Retry', () async {
      try {
        return await _dio.get<Object?>('/flaky');
      } on DioException catch (e) {
        // Re-fetching the same options shows up as a retry of the failed attempt.
        return _dio.fetch<Object?>(e.requestOptions);
      }
    });
  }

  @override
  Widget build(BuildContext context) => DemoPage(
    title: 'Dio',
    children: <Widget>[
      const DemoSection('Fake adapter', hint: 'Answers from memory, no internet needed.'),
      DemoButtons(<String, VoidCallback?>{
        'GET': () => _run('GET', () => _dio.get<Object?>('/posts')),
        'POST': () => _run(
          'POST',
          () => _dio.post<Object?>('/posts', data: <String, Object?>{'title': 'New post'}),
        ),
        'Upload': () => _run(
          'Upload',
          () => _dio.post<Object?>(
            '/upload',
            data: FormData.fromMap(<String, Object?>{
              'note': 'hello',
              'file': MultipartFile.fromBytes(List<int>.filled(2048, 7), filename: 'data.bin'),
            }),
          ),
        ),
        'Error 500': () => _run('Error', () => _dio.get<Object?>('/fail')),
        'Cancel': _cancel,
        'Retry': _retry,
      }),
      const DemoSection('Real network', hint: 'Needs internet access.'),
      DemoButtons(<String, VoidCallback?>{
        'GET httpbin.org': () => _run('httpbin', () => _real.get<Object?>('/get')),
      }),
      DemoStatus(_status),
    ],
  );
}
