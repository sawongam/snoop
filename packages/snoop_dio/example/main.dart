import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_dio/snoop_dio.dart';

void main() {
  final dio = Dio();
  dio.interceptors.insert(0, SnoopDioInterceptor(replayClient: dio));
  runApp(
    MaterialApp(
      builder: (context, child) => SnoopOverlay(child: child!),
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => dio.get<Object?>('https://example.com'),
            child: const Text('Call'),
          ),
        ),
      ),
    ),
  );
}
