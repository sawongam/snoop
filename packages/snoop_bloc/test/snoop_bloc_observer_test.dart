import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_bloc/snoop_bloc.dart';

import 'helpers/fakes.dart';

/// Whether the resolved bloc has `BlocObserver.onDone` (9.1 and up).
final bool _hasOnDone = () {
  try {
    // ignore: avoid_dynamic_calls
    (RecordingObserver() as dynamic).onDone;
    return true;
  } on NoSuchMethodError {
    return false;
  }
}();

void main() {
  final registry = Snoop.state;

  setUp(() {
    Snoop.reset();
    Bloc.observer = SnoopBlocObserver(enabled: true, logErrors: false);
    registry.maxHistory = 50;
  });

  test('tracks a cubit from creation to close', () async {
    final cubit = CounterCubit();
    expect(registry.count, 1);
    expect(registry[cubit]!.name, 'CounterCubit');
    expect(registry[cubit]!.kind, 'cubit');
    expect(registry[cubit]!.library, 'bloc');
    expect(registry[cubit]!.definedAt, contains('helpers/fakes.dart'));

    cubit
      ..increment()
      ..increment();
    final tracked = registry[cubit]!;
    expect(tracked.changeCount, 2);
    expect(tracked.currentState, 2);
    expect(tracked.history.map((r) => r.next), <int>[2, 1]);
    expect(tracked.history.first.event, isNull);

    await cubit.close();
    expect(registry.count, 0);
    expect(registry.disposed.single.name, 'CounterCubit');
  });

  test('records bloc transitions with their event and dispatch site', () async {
    final bloc = CounterBloc()..add(Incremented());
    await Future<void>.delayed(Duration.zero);

    final record = registry[bloc]!.history.single;
    expect(record.event, isA<Incremented>());
    expect(registry[bloc]!.kind, 'bloc');
    expect(record.previous, 0);
    expect(record.next, 1);
    expect(record.emittedFrom, contains('snoop_bloc_observer_test.dart'));
    await bloc.close();
  });

  test('records errors', () async {
    final bloc = CounterBloc()..add(Failed());
    await Future<void>.delayed(Duration.zero);

    final tracked = registry[bloc]!;
    expect(tracked.hasError, isTrue);
    expect(tracked.lastError, isA<StateError>());
    expect(registry.errorCount, 1);
    await bloc.close();
  });

  test('clearHistory and clearAllHistory keep blocs tracked', () async {
    final a = CounterCubit()..increment();
    final b = CounterCubit()..increment();

    registry.clearHistory(a);
    expect(registry[a]!.history, isEmpty);
    expect(registry[a]!.changeCount, 0);
    expect(registry[a]!.currentState, 1);
    expect(registry[b]!.history, hasLength(1));

    registry.clearAllHistory();
    expect(registry[b]!.history, isEmpty);
    expect(registry.count, 2);
    await Future.wait(<Future<void>>[a.close(), b.close()]);
  });

  test('history is bounded by maxHistory', () async {
    registry.maxHistory = 3;
    final cubit = CounterCubit();
    for (var i = 0; i < 10; i++) {
      cubit.increment();
    }
    expect(registry[cubit]!.history.map((r) => r.next), <int>[10, 9, 8]);
    expect(registry[cubit]!.changeCount, 10);
    await cubit.close();
  });

  test('two blocs of the same type are tracked separately, newest first', () async {
    final a = CounterCubit();
    final b = CounterCubit();
    expect(registry.live.map((s) => s.id), <int>[registry[b]!.id, registry[a]!.id]);
    await Future.wait(<Future<void>>[a.close(), b.close()]);
  });

  test('notifies listeners once per burst of changes', () async {
    var notifications = 0;
    void listener() => notifications++;
    registry.addListener(listener);
    final cubit = CounterCubit()
      ..increment()
      ..increment()
      ..increment();
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
    registry.removeListener(listener);
    await cubit.close();
  });

  test('records nothing when disabled', () async {
    Snoop.reset();
    Bloc.observer = SnoopBlocObserver(enabled: false);
    final cubit = CounterCubit()..increment();
    expect(registry.count, 0);
    expect(SnoopAdapters.ids, isEmpty);
    await cubit.close();
  });

  test('registers as a state adapter', () {
    expect(SnoopAdapters.has(SnoopAdapterKind.state), isTrue);
    expect(SnoopAdapters.ids, <String>['bloc']);
  });

  test('a cubit emit is one change without an event', () async {
    final cubit = CounterCubit()..increment();
    expect(registry[cubit]!.changeCount, 1);
    expect(registry[cubit]!.history.single.event, isNull);
    await cubit.close();
  });

  test('a bloc event is one change, not counted twice', () async {
    final bloc = CounterBloc()..add(Incremented());
    await Future<void>.delayed(Duration.zero);
    expect(registry[bloc]!.changeCount, 1);
    await bloc.close();
  });

  test('a handler that emits several times records each with the event and site', () async {
    final bloc = BurstBloc()..add(Burst());
    await Future<void>.delayed(Duration.zero);
    final history = registry[bloc]!.history;
    expect(history.map((r) => r.next), <int>[3, 2, 1]);
    expect(history.every((r) => r.event is Burst), isTrue);
    expect(history.every((r) => r.emittedFrom!.contains('snoop_bloc_observer_test')), isTrue);
    await bloc.close();
  });

  test('an event that emits nothing is recorded as no state change', () async {
    final bloc = BurstBloc()
      ..add(Incremented())
      ..add(Idle());
    await Future<void>.delayed(Duration.zero);
    final tracked = registry[bloc]!;
    expect(tracked.changeCount, 2);
    final idle = tracked.history.first;
    expect('${idle.event}', 'Idle (no state change)');
    expect(idle.previous, 1);
    expect(idle.next, 1);
    expect(idle.emittedFrom, contains('snoop_bloc_observer_test'));
    expect(tracked.history.last.emittedFrom, contains('snoop_bloc_observer_test'));
    await bloc.close();
  }, skip: !_hasOnDone);

  test('a throwing handler is an error, not a no-op entry', () async {
    late final BurstBloc bloc;
    await runZonedGuarded(() async {
      bloc = BurstBloc()..add(Crash());
      await Future<void>.delayed(Duration.zero);
    }, (error, stack) {});
    expect(registry[bloc]!.changeCount, 0);
    expect(registry[bloc]!.errorCount, 1);
    await bloc.close();
  });

  test('a bloc created before snoop joined is tracked on its first change', () async {
    final forwarding = ForwardingObserver();
    Bloc.observer = forwarding;
    final cubit = CounterCubit();
    expect(registry.count, 0);

    forwarding.observers.add(SnoopBlocObserver(enabled: true));
    cubit.increment();
    expect(registry.count, 1);
    expect(registry[cubit]!.name, 'CounterCubit');
    expect(registry[cubit]!.currentState, 1);
    await cubit.close();
  });

  test('closed blocs are retained, then evicted past retainDisposed', () async {
    registry.retainDisposed = 2;
    final cubits = <CounterCubit>[for (var i = 0; i < 3; i++) CounterCubit()];
    for (final c in cubits) {
      await c.close();
    }
    expect(registry.count, 0);
    expect(registry.disposed, hasLength(2));
    registry.retainDisposed = 20;
  });

  test('addError records the error and still calls super last', () async {
    final recording = RecordingObserver();
    final forwarding = ForwardingObserver()
      ..observers.addAll(<BlocObserver>[
        SnoopBlocObserver(enabled: true, logErrors: false),
        recording,
      ]);
    Bloc.observer = forwarding;
    final cubit = CounterCubit()..fail();
    final tracked = registry[cubit]!;
    expect(tracked.errorCount, 1);
    expect(tracked.lastErrorStackTrace, isNotNull);
    expect(recording.calls, <String>['onError']);
    await cubit.close();
  });

  test('two instances of one cubit are two sources with distinct ids', () async {
    final a = CounterCubit();
    final b = CounterCubit();
    expect(registry[a]!.id, isNot(registry[b]!.id));
    expect(registry.count, 2);
    await Future.wait(<Future<void>>[a.close(), b.close()]);
  });

  test('states with a throwing toString and hashCode never break the app', () async {
    final cubit = HostileCubit()..bump();
    expect(registry[cubit]!.changeCount, 1);
    await cubit.close();
  });

  testWidgets('the State tab lists a bloc and its history', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SnoopOverlay(enabled: true, child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    );
    final bloc = CounterBloc()..add(Incremented());
    final other = CounterBloc();
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('snoop.bubble')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('State 2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CounterBloc #'), findsNWidgets(2));

    await tester.tap(find.textContaining('CounterBloc #${registry[bloc]!.id}'));
    await tester.pumpAndSettle();
    expect(find.text('▸ Incremented'), findsOneWidget);
    await tester.runAsync(() => Future.wait(<Future<void>>[bloc.close(), other.close()]));
  });

  test('call sites skip bloc frames', () {
    final trace = StackTrace.fromString('''
#0      SnoopBlocObserver.onEvent (package:snoop_bloc/src/snoop_bloc_observer.dart:61:5)
#1      Bloc.add (package:bloc/src/bloc.dart:82:24)
#2      _HomeState._tap (package:my_app/home/home_page.dart:42:11)
''');
    expect(SnoopCallSite.resolve(trace: trace), 'package:my_app/home/home_page.dart:42');
  });
}
