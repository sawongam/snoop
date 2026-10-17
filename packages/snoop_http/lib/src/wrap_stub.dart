import 'package:http/http.dart' as http;

/// The `dart:io` flavour of a response copy, or `null` where there is none.
http.StreamedResponse? wrapIoResponse(http.StreamedResponse original, Stream<List<int>> stream) =>
    null;
