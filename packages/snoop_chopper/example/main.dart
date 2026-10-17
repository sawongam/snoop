import 'package:chopper/chopper.dart';
import 'package:flutter/material.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_chopper/snoop_chopper.dart';

late final ChopperClient chopper;

void setUpChopper() {
  chopper = ChopperClient(
    baseUrl: Uri.parse('https://api.example.com'),
    converter: const JsonConverter(),
    interceptors: [SnoopChopperInterceptor(replayClient: () => chopper)],
  );
}

void main() {
  setUpChopper();
  runApp(
    MaterialApp(
      builder: (context, child) => SnoopOverlay(child: child!),
      home: const Scaffold(body: Center(child: Text('Hello'))),
    ),
  );
}
