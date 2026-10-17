import 'package:bloc/bloc.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  void increment() => emit(state + 1);
}

sealed class CounterEvent {}

final class Incremented extends CounterEvent {
  @override
  String toString() => 'Incremented';
}

final class Failed extends CounterEvent {}

class CounterBloc extends Bloc<CounterEvent, int> {
  CounterBloc() : super(0) {
    on<Incremented>((event, emit) => emit(state + 1));
    on<Failed>((event, emit) => addError(StateError('boom')));
  }
}
