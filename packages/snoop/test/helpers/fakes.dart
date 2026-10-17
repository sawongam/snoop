import 'package:snoop/snoop.dart';

/// A plain object standing in for a bloc, provider or store.
class FakeSource {
  FakeSource(this.value);

  int value;
}

final class Incremented {
  @override
  String toString() => 'Incremented';
}

/// Registers one network and one state adapter, as installing `snoop_http`
/// and `snoop_bloc` would, so the Network and State tabs show.
void registerFakeAdapters() {
  SnoopAdapters.register('fake_http', SnoopAdapterKind.network);
  SnoopAdapters.register('fake_state', SnoopAdapterKind.state);
}

/// Tracks [source] like a state adapter would and applies [increments],
/// each recorded as an [Incremented] event when [withEvents] is set.
SnoopStateSource trackFake(
  FakeSource source, {
  String name = 'CounterCubit',
  String kind = 'cubit',
  int increments = 0,
  bool withEvents = false,
}) {
  final tracked = Snoop.state.track(
    source,
    name: name,
    kind: kind,
    library: 'fake_state',
    initialState: source.value,
  );
  for (var i = 0; i < increments; i++) {
    final previous = source.value;
    source.value++;
    Snoop.state.change(source, previous, source.value, event: withEvents ? Incremented() : null);
  }
  return tracked;
}
