/// Provider adapter for snoop: tracks `ChangeNotifier`s and other
/// `Listenable`s in the State tab.
///
/// ```dart
/// ChangeNotifierProvider(create: (_) => SnoopListenable.track(CartModel()));
/// ```
library;

export 'src/snoop_listenable.dart' show SnoopListenable;
export 'src/snoop_providers.dart' show SnoopChangeNotifierProvider, SnoopListenableProvider;
