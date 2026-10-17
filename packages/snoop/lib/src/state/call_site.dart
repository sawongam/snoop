/// Resolves where in the app a state change or call came from, by walking
/// the stack past framework and library frames.
abstract final class SnoopCallSite {
  /// Prefixes skipped by every resolution: Flutter, test and async helpers,
  /// and the snoop packages themselves. Adapters add their library's
  /// prefixes through [ignore].
  static const List<String> coreIgnored = <String>[
    'package:async/',
    'package:flutter/',
    'package:flutter_test/',
    'package:rxdart/',
    'package:snoop/',
    'package:snoop_bloc/',
    'package:snoop_chopper/',
    'package:snoop_dio/',
    'package:snoop_getx/',
    'package:snoop_http/',
    'package:snoop_mobx/',
    'package:snoop_provider/',
    'package:snoop_riverpod/',
    'package:snoop_signals/',
    'package:stack_trace/',
    'package:stream_transform/',
    'package:test_api/',
  ];

  static final List<String> _ignored = <String>[...coreIgnored];

  /// Every prefix skipped today: [coreIgnored] plus what adapters added.
  static List<String> get ignored => List<String>.unmodifiable(_ignored);

  /// Skips frames whose location starts with any of [prefixes] (e.g.
  /// `'package:bloc/'`) from now on. Prefixes already present are ignored.
  static void ignore(Iterable<String> prefixes) {
    for (final prefix in prefixes) {
      if (!_ignored.contains(prefix)) _ignored.add(prefix);
    }
  }

  // VM:  #3  Foo.bar (package:app/src/foo.dart:42:7)
  //      #3  main (file:///home/me/app/test/foo_test.dart:12:5)
  // Web: packages/app/src/foo.dart 42:7   bar
  static final RegExp _frame = RegExp(
    r'(package:[^\s()]+?\.dart|packages/[^\s()]+?\.dart|file://[^\s()]+?\.dart)[: ](\d+)',
  );

  /// Returns the first frame of [trace] (default: the current stack) that
  /// isn't in [ignored] or [extra], formatted as `package:app/path.dart:line`.
  ///
  /// Returns `null` if no such frame exists.
  static String? resolve({List<String> extra = const <String>[], StackTrace? trace}) {
    final lines = (trace ?? StackTrace.current).toString().split('\n');
    for (final line in lines) {
      final match = _frame.firstMatch(line);
      if (match == null) continue;
      var path = match.group(1)!;
      if (path.startsWith('packages/')) path = 'package:${path.substring('packages/'.length)}';
      if (_ignored.any(path.startsWith) || extra.any(path.startsWith)) continue;
      return '$path:${match.group(2)}';
    }
    return null;
  }
}
