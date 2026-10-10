/// Location prefixes that are never reported as a call site: the Dart/Flutter
/// frameworks, the bloc and dio packages, common stream/async helpers and this
/// package itself.
const List<String> defaultIgnoredLocations = <String>[
  'package:bloc/',
  'package:bloc_concurrency/',
  'package:snoop/',
  'package:dio/',
  'package:flutter/',
  'package:flutter_bloc/',
  'package:flutter_test/',
  'package:hydrated_bloc/',
  'package:nested/',
  'package:provider/',
  'package:replay_bloc/',
  'package:rxdart/',
  'package:stack_trace/',
  'package:stream_transform/',
  'package:test_api/',
];

// VM:  #3  Foo.bar (package:app/src/foo.dart:42:7)
//      #3  main (file:///home/me/app/test/foo_test.dart:12:5)
// Web: packages/app/src/foo.dart 42:7   bar
final RegExp _frame = RegExp(
  r'(package:[^\s()]+?\.dart|packages/[^\s()]+?\.dart|file://[^\s()]+?\.dart)[: ](\d+)',
);

/// Returns the first frame of [trace] (default: the current stack) that isn't
/// in [ignored], formatted as `package:app/path.dart:line`.
///
/// Returns `null` if no such frame exists.
String? resolveCallSite({List<String> ignored = defaultIgnoredLocations, StackTrace? trace}) {
  final lines = (trace ?? StackTrace.current).toString().split('\n');
  for (final line in lines) {
    final match = _frame.firstMatch(line);
    if (match == null) continue;
    var path = match.group(1)!;
    if (path.startsWith('packages/')) path = 'package:${path.substring('packages/'.length)}';
    if (ignored.any(path.startsWith)) continue;
    return '$path:${match.group(2)}';
  }
  return null;
}
