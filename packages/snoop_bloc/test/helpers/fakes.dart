import 'package:bloc/bloc.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  void increment() => emit(state + 1);

  void fail() => addError(StateError('x'), StackTrace.current);
}

sealed class CounterEvent {}

final class Incremented extends CounterEvent {
  @override
  String toString() => 'Incremented';
}

final class Failed extends CounterEvent {}

final class Crash extends CounterEvent {}

final class Burst extends CounterEvent {
  @override
  String toString() => 'Burst';
}

final class Idle extends CounterEvent {
  @override
  String toString() => 'Idle';
}

class CounterBloc extends Bloc<CounterEvent, int> {
  CounterBloc() : super(0) {
    on<Incremented>((event, emit) => emit(state + 1));
    on<Failed>((event, emit) => addError(StateError('boom')));
  }
}

class BurstBloc extends Bloc<CounterEvent, int> {
  BurstBloc() : super(0) {
    on<Burst>((event, emit) {
      emit(state + 1);
      emit(state + 1);
      emit(state + 1);
    });
    on<Idle>((event, emit) {});
    on<Crash>((event, emit) => throw StateError('crash'));
    on<Incremented>((event, emit) => emit(state + 1));
  }
}

/// A state whose `toString` and `hashCode` throw. `==` stays the default,
/// because bloc itself compares states with it.
class Hostile {
  const Hostile(this.n);

  final int n;

  @override
  String toString() => throw StateError('toString');

  @override
  // ignore: hash_and_equals
  int get hashCode => throw StateError('hashCode');
}

class HostileCubit extends Cubit<Hostile> {
  HostileCubit() : super(const Hostile(0));

  void bump() => emit(Hostile(state.n + 1));
}

/// Records which observer callbacks ran, in order.
class RecordingObserver extends BlocObserver {
  final List<String> calls = <String>[];

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    calls.add('onError');
    super.onError(bloc, error, stackTrace);
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    calls.add('onChange');
    super.onChange(bloc, change);
  }
}

/// Forwards to a list of observers that may grow after blocs were created,
/// like an app observer that adds snoop later.
class ForwardingObserver extends BlocObserver {
  final List<BlocObserver> observers = <BlocObserver>[];

  @override
  // ignore: must_call_super
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    for (final o in observers) {
      o.onChange(bloc, change);
    }
  }

  @override
  // ignore: must_call_super
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    for (final o in observers) {
      o.onError(bloc, error, stackTrace);
    }
  }
}
