import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_bloc/snoop_bloc.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  void increment() => emit(state + 1);
}

void main() {
  Bloc.observer = SnoopBlocObserver();
  runApp(
    MaterialApp(
      builder: (context, child) => SnoopOverlay(child: child!),
      home: const CounterPage(),
    ),
  );
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  final CounterCubit _cubit = CounterCubit();

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: StreamBuilder<int>(
        stream: _cubit.stream,
        initialData: _cubit.state,
        builder: (context, snapshot) => Text('${snapshot.data}'),
      ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: _cubit.increment,
      child: const Icon(Icons.add),
    ),
  );
}
