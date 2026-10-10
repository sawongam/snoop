import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

import 'helpers/fakes.dart';

void main() {
  final registry = Snoop.bloc;

  setUp(() {
    Bloc.observer = SnoopBlocObserver(enabled: true, logErrors: false);
    Snoop.reset();
    registry.maxHistory = 50;
  });

  test('tracks a cubit from creation to close', () async {
    final cubit = CounterCubit();
    expect(registry.count, 1);
    expect(registry[cubit]!.name, 'CounterCubit');
    expect(registry[cubit]!.definedAt, contains('helpers/fakes.dart'));

    cubit
      ..increment()
      ..increment();
    final tracked = registry[cubit]!;
    expect(tracked.changeCount, 2);
    expect(tracked.currentState, 2);
    expect(tracked.history.map((r) => r.nextState), <int>[2, 1]);
    expect(tracked.history.first.event, isNull);

    await cubit.close();
    expect(registry.count, 0);
  });

  test('records bloc transitions with their event and dispatch site', () async {
    final bloc = CounterBloc()..add(Incremented());
    await Future<void>.delayed(Duration.zero);

    final record = registry[bloc]!.history.single;
    expect(record.event, isA<Incremented>());
    expect(record.currentState, 0);
    expect(record.nextState, 1);
    expect(record.emittedFrom, contains('bloc_registry_test.dart'));
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
    expect(registry[cubit]!.history.map((r) => r.nextState), <int>[10, 9, 8]);
    expect(registry[cubit]!.changeCount, 10);
    await cubit.close();
  });

  test('two blocs of the same type are tracked separately, newest first', () async {
    final a = CounterCubit();
    final b = CounterCubit();
    expect(registry.blocs.map((t) => t.bloc), <Object>[b, a]);
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
    Bloc.observer = SnoopBlocObserver(enabled: false);
    final cubit = CounterCubit()..increment();
    expect(registry.count, 0);
    await cubit.close();
  });
}
