// MultiBlocObserver ships with bloc 9.2, so this file does not compile
// against older versions of bloc.
import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_bloc/snoop_bloc.dart';

import 'helpers/fakes.dart';

void main() {
  setUp(Snoop.reset);

  test('MultiBlocObserver forwards to snoop and to the others', () async {
    final recording = RecordingObserver();
    Bloc.observer = MultiBlocObserver(
      observers: <BlocObserver>[recording, SnoopBlocObserver(enabled: true)],
    );
    final cubit = CounterCubit()..increment();
    expect(recording.calls, <String>['onChange']);
    expect(Snoop.state[cubit]!.changeCount, 1);
    await cubit.close();
  });

  test('onDone is forwarded, so no-op events are recorded', () async {
    Bloc.observer = MultiBlocObserver(observers: <BlocObserver>[SnoopBlocObserver(enabled: true)]);
    final bloc = BurstBloc()..add(Idle());
    await Future<void>.delayed(Duration.zero);
    expect(Snoop.state[bloc]!.history.single.event.toString(), endsWith('(no state change)'));
    await bloc.close();
  });
}
