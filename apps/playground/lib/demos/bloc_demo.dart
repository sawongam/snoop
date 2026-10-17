import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:snoop_playground/demos/demo_page.dart';

/// A counter cubit.
class CounterCubit extends Cubit<int> {
  /// Creates a counter at zero.
  CounterCubit() : super(0);

  /// Adds one.
  void increment() => emit(state + 1);

  /// Subtracts one.
  void decrement() => emit(state - 1);
}

/// Todo events.
sealed class TodoEvent {
  const TodoEvent();
}

/// Adds a todo with [title].
class TodoAdded extends TodoEvent {
  /// Creates the event.
  const TodoAdded(this.title);

  /// What to do.
  final String title;

  @override
  String toString() => 'TodoAdded($title)';
}

/// Toggles the todo at [index].
class TodoToggled extends TodoEvent {
  /// Creates the event.
  const TodoToggled(this.index);

  /// Position in the list.
  final int index;

  @override
  String toString() => 'TodoToggled($index)';
}

/// Removes finished todos. Emits nothing when there are none.
class TodosCleared extends TodoEvent {
  /// Creates the event.
  const TodosCleared();
}

/// A todo item.
class Todo {
  /// Creates a todo.
  const Todo(this.title, {this.done = false});

  /// What to do.
  final String title;

  /// Whether it is finished.
  final bool done;

  /// The map the State tab shows.
  Map<String, Object?> toJson() => <String, Object?>{'title': title, 'done': done};
}

/// A bloc with events.
class TodoBloc extends Bloc<TodoEvent, List<Todo>> {
  /// Creates an empty list.
  TodoBloc() : super(const <Todo>[]) {
    on<TodoAdded>((event, emit) => emit(<Todo>[...state, Todo(event.title)]));
    on<TodoToggled>((event, emit) {
      emit(<Todo>[
        for (final (i, todo) in state.indexed)
          i == event.index ? Todo(todo.title, done: !todo.done) : todo,
      ]);
    });
    on<TodosCleared>((event, emit) {
      if (state.any((todo) => todo.done)) emit(state.where((todo) => !todo.done).toList());
    });
  }
}

/// A cubit whose operations fail and report the error.
class FlakyCubit extends Cubit<String> {
  /// Creates the cubit.
  FlakyCubit() : super('ok');

  /// Reports a failure through `addError`, which reaches `BlocObserver.onError`.
  void fail() => addError(StateError('Something went wrong'), StackTrace.current);
}

/// Bloc: a counter cubit, a todo bloc with events and a cubit that reports errors.
class BlocDemo extends StatelessWidget {
  /// Creates the screen.
  const BlocDemo({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider<CounterCubit>(create: (_) => CounterCubit()),
      BlocProvider<TodoBloc>(create: (_) => TodoBloc()),
      BlocProvider<FlakyCubit>(create: (_) => FlakyCubit()),
    ],
    child: Builder(
      builder: (context) => DemoPage(
        title: 'Bloc',
        children: <Widget>[
          const DemoSection('Counter cubit'),
          BlocBuilder<CounterCubit, int>(
            builder: (context, count) => Text('Count: $count', key: const Key('count')),
          ),
          DemoButtons(<String, VoidCallback?>{
            '+1': context.read<CounterCubit>().increment,
            '-1': context.read<CounterCubit>().decrement,
          }),
          const DemoSection('Todo bloc', hint: 'Events show up next to each state change.'),
          BlocBuilder<TodoBloc, List<Todo>>(
            builder: (context, todos) => Text(
              todos.isEmpty
                  ? 'No todos'
                  : todos.map((t) => '${t.done ? '[x]' : '[ ]'} ${t.title}').join('\n'),
              key: const Key('todos'),
            ),
          ),
          DemoButtons(<String, VoidCallback?>{
            'Add': () => context.read<TodoBloc>().add(
              TodoAdded('Todo ${context.read<TodoBloc>().state.length + 1}'),
            ),
            'Toggle first': () => context.read<TodoBloc>().add(const TodoToggled(0)),
            'Clear done': () => context.read<TodoBloc>().add(const TodosCleared()),
          }),
          const DemoSection('Bloc that fails', hint: 'The error count and stack trace appear.'),
          DemoButtons(<String, VoidCallback?>{'Fail': context.read<FlakyCubit>().fail}),
        ],
      ),
    ),
  );
}
