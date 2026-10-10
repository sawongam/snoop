import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/src/bloc/call_site.dart';

void main() {
  test('skips framework frames and returns the first app frame (VM)', () {
    final trace = StackTrace.fromString('''
#0      StackTrace.current (dart:core-patch/stack_trace_patch.dart:12:28)
#1      SnoopBlocObserver.onEvent (package:snoop/src/bloc/inspector_bloc_observer.dart:61:5)
#2      Bloc.add (package:bloc/src/bloc.dart:82:24)
#3      _HomeState._tap (package:my_app/home/home_page.dart:42:11)
#4      _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1170:21)
''');
    expect(resolveCallSite(trace: trace), 'package:my_app/home/home_page.dart:42');
  });

  test('normalizes web frames', () {
    final trace = StackTrace.fromString('''
packages/bloc/src/bloc.dart 82:24                     add
packages/my_app/home/home_page.dart 42:11             [_tap]
''');
    expect(resolveCallSite(trace: trace), 'package:my_app/home/home_page.dart:42');
  });

  test('honours extra ignored locations', () {
    final trace = StackTrace.fromString('''
#1      AppObserver.onEvent (package:my_app/core/app_observer.dart:10:5)
#2      _HomeState._tap (package:my_app/home/home_page.dart:42:11)
''');
    expect(
      resolveCallSite(
        trace: trace,
        ignored: <String>[...defaultIgnoredLocations, 'package:my_app/core/'],
      ),
      'package:my_app/home/home_page.dart:42',
    );
  });

  test('returns null when only framework frames exist', () {
    final trace = StackTrace.fromString('#0      Bloc.add (package:bloc/src/bloc.dart:82:24)');
    expect(resolveCallSite(trace: trace), isNull);
  });
}
