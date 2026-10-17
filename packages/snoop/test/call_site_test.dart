import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

void main() {
  test('skips framework and snoop frames and returns the first app frame (VM)', () {
    final trace = StackTrace.fromString('''
#0      StackTrace.current (dart:core-patch/stack_trace_patch.dart:12:28)
#1      SnoopBlocObserver.onEvent (package:snoop_bloc/src/snoop_bloc_observer.dart:61:5)
#2      Something.run (package:snoop/src/state/state_registry.dart:82:24)
#3      _HomeState._tap (package:my_app/home/home_page.dart:42:11)
#4      _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1170:21)
''');
    expect(SnoopCallSite.resolve(trace: trace), 'package:my_app/home/home_page.dart:42');
  });

  test('normalizes web frames', () {
    final trace = StackTrace.fromString('''
packages/flutter/src/widgets/framework.dart 82:24       build
packages/my_app/home/home_page.dart 42:11             [_tap]
''');
    expect(SnoopCallSite.resolve(trace: trace), 'package:my_app/home/home_page.dart:42');
  });

  test('honours extra ignored locations', () {
    final trace = StackTrace.fromString('''
#1      AppObserver.onEvent (package:my_app/core/app_observer.dart:10:5)
#2      _HomeState._tap (package:my_app/home/home_page.dart:42:11)
''');
    expect(
      SnoopCallSite.resolve(trace: trace, extra: <String>['package:my_app/core/']),
      'package:my_app/home/home_page.dart:42',
    );
  });

  test('ignore and adapter registration add prefixes', () {
    final trace = StackTrace.fromString('''
#1      Lib.call (package:some_lib/src/lib.dart:10:5)
#2      _HomeState._tap (package:my_app/home/home_page.dart:42:11)
''');
    expect(SnoopCallSite.resolve(trace: trace), 'package:some_lib/src/lib.dart:10');
    SnoopAdapters.register(
      'some_lib',
      SnoopAdapterKind.state,
      ignoredLocations: <String>['package:some_lib/'],
    );
    expect(SnoopCallSite.resolve(trace: trace), 'package:my_app/home/home_page.dart:42');
    expect(SnoopCallSite.ignored.where((p) => p == 'package:some_lib/'), hasLength(1));
  });

  test('a snoop-like app name is not ignored', () {
    final trace = StackTrace.fromString('#0      main (package:snoopy/main.dart:3:1)');
    expect(SnoopCallSite.resolve(trace: trace), 'package:snoopy/main.dart:3');
  });

  test('returns null when only framework frames exist', () {
    final trace = StackTrace.fromString(
      '#0      State.build (package:flutter/src/widgets/framework.dart:82:24)',
    );
    expect(SnoopCallSite.resolve(trace: trace), isNull);
  });
}
