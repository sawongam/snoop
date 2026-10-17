/// MobX adapter for snoop: every store's observables in the State tab.
///
/// ```dart
/// void main() {
///   SnoopMobx.install(); // after configuring MobX
///   runApp(const App());
/// }
/// ```
library;

export 'src/snoop_mobx.dart' show SnoopMobx, SnoopMobxGroup;
