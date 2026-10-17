/// Riverpod adapter for snoop: every provider in the State tab.
///
/// ```dart
/// runApp(ProviderScope(observers: [SnoopProviderObserver()], child: const App()));
/// ```
library;

export 'src/snoop_provider_observer.dart' show SnoopProviderObserver;
