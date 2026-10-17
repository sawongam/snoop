/// Not available where there is no `dart:io` (web).
Future<Uri> startFakeServer() =>
    Future<Uri>.error(UnsupportedError('The local fake server needs dart:io.'));

/// Not available where there is no `dart:io` (web).
Future<void> stopFakeServer() async {}
