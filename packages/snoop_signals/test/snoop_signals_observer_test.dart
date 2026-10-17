// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_core/signals_core.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_signals/snoop_signals.dart';

/// Records every call it gets, optionally throwing from each.
class FakeObserver extends SignalsObserver {
  FakeObserver({this.throws = false});

  final bool throws;
  final List<String> calls = <String>[];

  void _log(String name) {
    calls.add(name);
    if (throws) throw StateError('downstream failed');
  }

  @override
  void onSignalCreated<T>(Signal<T> instance, T value) => _log('signalCreated');

  @override
  void onSignalUpdated<T>(Signal<T> instance, T value) => _log('signalUpdated');

  @override
  void onComputedCreated<T>(Computed<T> instance) => _log('computedCreated');

  @override
  void onComputedUpdated<T>(Computed<T> instance, T value) => _log('computedUpdated');

  @override
  void onEffectCreated(Effect instance) => _log('effectCreated');

  @override
  void onEffectCalled(Effect instance) => _log('effectCalled');

  @override
  void onEffectRemoved(Effect instance) => _log('effectRemoved');
}

/// Whether the resolved signals_core calls `onEffectCalled`. 6.0.0 declares
/// it on the observer but never calls it; 6.3.1 and 7 call it on activation.
final bool reportsEffectRuns = () {
  final saved = SignalsObserver.instance;
  final probe = FakeObserver();
  SignalsObserver.instance = probe;
  effect(() {})();
  SignalsObserver.instance = saved;
  return probe.calls.contains('effectCalled');
}();

void main() {
  final registry = Snoop.state;
  late SignalsObserver? original;
  late FakeObserver previous;

  setUp(() {
    original = SignalsObserver.instance;
    Snoop.reset();
    previous = FakeObserver();
    SignalsObserver.instance = previous;
  });

  tearDown(() => SignalsObserver.instance = original);

  test('a signal created after install is tracked with its initial value', () {
    SnoopSignals.install();
    final count = signal(0, debugLabel: 'count');

    final source = registry[count]!;
    expect(source.name, 'count');
    expect(source.kind, 'signal');
    expect(source.library, 'signals');
    expect(source.currentState, 0);
    expect(source.weak, isTrue);
    expect(source.definedAt, contains('snoop_signals_observer_test.dart'));

    count.value = 1;
    count.value = 2;
    expect(source.changeCount, 2);
    expect(source.history.map((c) => c.next), <int>[2, 1]);
    expect(source.history.first.previous, 1);
    expect(source.history.first.hasPrevious, isTrue);
    expect(source.history.first.emittedFrom, contains('snoop_signals_observer_test.dart'));
  });

  test('an unlabelled signal is named by type and id', () {
    SnoopSignals.install();
    final s = signal('x');
    expect(registry[s]!.name, 'Signal<String>#${s.globalId}');
  });

  test('a signal created before install is tracked on its first update', () {
    final count = signal(0);
    SnoopSignals.install();
    expect(registry[count], isNull);

    count.value = 5;
    final source = registry[count]!;
    expect(source.currentState, 5);
    expect(source.history.single.hasPrevious, isFalse);
    expect(source.history.single.next, 5);

    count.value = 6;
    expect(source.history.first.hasPrevious, isTrue);
    expect(source.history.first.previous, 5);
  });

  test('batch records one change per signal', () {
    SnoopSignals.install();
    final a = signal(0);
    final b = signal(0);
    batch(() {
      a.value = 1;
      b.value = 2;
    });
    expect(registry[a]!.changeCount, 1);
    expect(registry[b]!.changeCount, 1);
  });

  test('a ListSignal add keeps the old list in the snapshot', () {
    SnoopSignals.install();
    final list = listSignal<int>(<int>[1]);
    final source = registry[list]!;
    expect(source.kind, 'list signal');
    expect(source.snapshot, isTrue);

    list.add(2);
    final change = source.history.single;
    expect(change.previous, <Object?>[1]);
    expect(change.next, <Object?>[1, 2]);

    list.add(3);
    expect(source.history.first.previous, <Object?>[1, 2]);
  });

  test('map and set signals are snapshots too', () {
    SnoopSignals.install();
    final map = mapSignal<String, int>(<String, int>{'a': 1});
    final set = setSignal<int>(<int>{1});
    expect(registry[map]!.kind, 'map signal');
    expect(registry[set]!.kind, 'set signal');
    expect(registry[map]!.snapshot, isTrue);
    expect(registry[set]!.snapshot, isTrue);
  });

  test('computed is off by default', () {
    SnoopSignals.install();
    final a = signal(1);
    final doubled = computed(() => a.value * 2)..value;
    a.value = 2;
    doubled.value;
    expect(registry[doubled], isNull);
    expect(registry.count, 1);
  });

  test('computed on: tracked and updated once read', () {
    SnoopSignals.install(includeComputed: true);
    final a = signal(1);
    final doubled = computed(() => a.value * 2, debugLabel: 'doubled');
    final source = registry[doubled]!;
    expect(source.kind, 'computed');
    expect(source.name, 'doubled');
    expect(source.changeCount, 0);

    expect(doubled.value, 2);
    expect(source.currentState, 2);
    expect(source.history.single.hasPrevious, isFalse);

    a.value = 5;
    expect(doubled.value, 10);
    expect(source.currentState, 10);
    expect(source.history.first.previous, 2);
  });

  test('effects: off by default, on records runs and disposal', () {
    SnoopSignals.install();
    final off = signal(0);
    effect(() => off.value)();
    expect(registry.sources.where((s) => s.kind == 'effect'), isEmpty);

    SnoopSignals.uninstall();
    SnoopSignals.install(includeEffects: true);
    final trigger = signal(0);
    final dispose = effect(() => trigger.value);
    final source = registry.sources.firstWhere((s) => s.kind == 'effect');
    expect(source.hasState, isFalse);
    expect(source.history.map((c) => c.event), reportsEffectRuns ? <Object?>['ran'] : isEmpty);

    // signals_core reports only the first run of an effect to the observer.
    trigger.value = 1;
    expect(source.history.map((c) => c.event), reportsEffectRuns ? <Object?>['ran'] : isEmpty);

    dispose();
    expect(source.isDisposed, isTrue);
    expect(registry.disposed, contains(source));
  });

  test('explicit dispose marks the source disposed right away', () {
    SnoopSignals.install();
    final s = signal(0)..dispose();
    expect(registry[s], isNull);
    expect(registry.disposed.single.currentState, 0);
  });

  test('a collected signal is disposed through the finalizer', () {
    SnoopSignals.install();
    final s = signal(0);
    final source = registry[s]!;
    registry.debugCollect(source);
    expect(source.isDisposed, isTrue);
    expect(source.details['collected'], isTrue);
  });

  test('shouldTrack drops signals', () {
    var asked = 0;
    SnoopSignals.install(
      shouldTrack: (s) {
        asked++;
        return s.debugLabel != 'tick';
      },
    );
    final tick = signal(0, debugLabel: 'tick');
    final kept = signal(0, debugLabel: 'kept');
    tick.value = 1;
    tick.value = 2;
    expect(registry[tick], isNull);
    expect(registry[kept], isNotNull);
    expect(asked, 2);
  });

  test('the previous observer receives every call', () {
    SnoopSignals.install(includeComputed: true, includeEffects: true);
    final a = signal(0);
    final c = computed(() => a.value + 1)..value;
    a.value = 1;
    final stop = effect(() => a.value);
    stop();

    expect(
      previous.calls,
      containsAll(<String>[
        'signalCreated',
        'signalUpdated',
        'computedCreated',
        'computedUpdated',
        'effectCreated',
        if (reportsEffectRuns) 'effectCalled',
        'effectRemoved',
      ]),
    );
    expect(c.value, 2);
  });

  test('forwarding happens even when recording is disabled', () {
    SignalsObserver.instance = SnoopSignalsObserver(next: previous, enabled: false);
    final a = signal(0);
    a.value = 1;
    expect(previous.calls, <String>['signalCreated', 'signalUpdated']);
    expect(registry.count, 0);
    expect(SnoopAdapters.has(SnoopAdapterKind.state), isFalse);
  });

  test('a throwing previous observer breaks neither the app nor snoop', () {
    final thrower = FakeObserver(throws: true);
    SignalsObserver.instance = SnoopSignalsObserver(next: thrower);
    final reported = <FlutterErrorDetails>[];
    final oldHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = oldHandler);

    final a = signal(0);
    a.value = 1;
    expect(a.value, 1);
    expect(registry[a]!.changeCount, 1);
    expect(thrower.calls, <String>['signalCreated', 'signalUpdated']);
    expect(reported, hasLength(2));
    expect(reported.first.library, 'snoop_signals');
  });

  test('install twice leaves one wrapper; uninstall restores the previous observer', () {
    final first = SnoopSignals.install()!;
    final second = SnoopSignals.install(includeComputed: true)!;
    expect(second, same(first));
    expect(SignalsObserver.instance, same(first));
    expect(first.next, same(previous));

    SnoopSignals.uninstall();
    expect(SignalsObserver.instance, same(previous));
    SnoopSignals.uninstall();
    expect(SignalsObserver.instance, same(previous));
  });

  test('install with enabled false installs nothing', () {
    expect(SnoopSignals.install(enabled: false), isNull);
    expect(SignalsObserver.instance, same(previous));
  });

  test('install registers a state adapter', () {
    SnoopSignals.install();
    expect(SnoopAdapters.all['signals'], SnoopAdapterKind.state);
  });

  test('an unprintable value never throws', () {
    SnoopSignals.install();
    final s = signal<Object>(_Bad());
    s.value = _Bad();
    expect(registry[s]!.changeCount, 1);
  });

  // Stack captures dominate the cost, so the bound is 500 ms without them and
  // looser with them, where a loaded machine can take a few times longer.
  for (final (captureCallSites, boundMs) in <(bool, int)>[(false, 500), (true, 3000)]) {
    test('10 000 updates (call sites: $captureCallSites) stay fast and capped', () {
      SnoopSignals.install(captureCallSites: captureCallSites);
      registry.maxHistory = 50;
      final s = signal(0);
      final watch = Stopwatch()..start();
      for (var i = 1; i <= 10000; i++) {
        s.value = i;
      }
      watch.stop();
      final source = registry[s]!;
      expect(source.history.length, 50);
      expect(source.changeCount, 10000);
      expect(source.currentState, 10000);
      expect(watch.elapsedMilliseconds, lessThan(boundMs));
    });
  }

  testWidgets('the State tab lists a signal and its history', (tester) async {
    SnoopSignals.install();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SnoopOverlay(enabled: true, child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    );
    final count = signal(0, debugLabel: 'count');
    count.value = 1;
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('snoop.bubble')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('State 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('count'), findsWidgets);
  });
}

class _Bad {
  @override
  String toString() => throw StateError('no');
}
