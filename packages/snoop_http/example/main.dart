import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:snoop/snoop.dart';
import 'package:snoop_http/snoop_http.dart';

final client = SnoopHttpClient(http.Client());

// Also records top-level `http.get(...)` and `http.Client()`.
void main() => SnoopHttp.runZoned(() => runApp(const App()));

/// The demo app.
class App extends StatelessWidget {
  /// Creates the app.
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => SnoopOverlay(child: child!),
    home: Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => client.get(Uri.https('example.com')),
          child: const Text('Call'),
        ),
      ),
    ),
  );
}
