import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:snoop_provider/src/snoop_listenable.dart';

T _tracked<T extends Listenable?>(
  T value,
  String? name,
  Object? Function(T notifier)? state,
  bool enabled,
) {
  if (value == null) return value;
  SnoopListenable.track<Listenable>(
    value,
    name: name,
    state: state == null ? null : (n) => state(n as T),
    enabled: enabled,
  );
  return value;
}

/// A [ChangeNotifierProvider] that records its notifier in snoop's State tab.
///
/// A drop-in replacement: it forwards every argument to
/// [ChangeNotifierProvider] and tracks what `create` (or `value`) returns with
/// [SnoopListenable.track].
///
/// ```dart
/// SnoopChangeNotifierProvider<CartModel>(create: (_) => CartModel(), child: const Shop());
/// ```
class SnoopChangeNotifierProvider<T extends ChangeNotifier?> extends ChangeNotifierProvider<T> {
  /// Creates a notifier with [create], tracks it and disposes it when the
  /// provider leaves the tree, like [ChangeNotifierProvider].
  ///
  /// [name], [state] and [enabled] are those of [SnoopListenable.track].
  SnoopChangeNotifierProvider({
    required Create<T> create,
    super.key,
    super.lazy,
    super.builder,
    super.child,
    String? name,
    Object? Function(T notifier)? state,
    bool enabled = kDebugMode,
  }) : super(create: (context) => _tracked<T>(create(context), name, state, enabled));

  /// Provides and tracks an existing [value], like
  /// [ChangeNotifierProvider.value].
  SnoopChangeNotifierProvider.value({
    required T value,
    super.key,
    super.builder,
    super.child,
    String? name,
    Object? Function(T notifier)? state,
    bool enabled = kDebugMode,
  }) : super.value(value: _tracked<T>(value, name, state, enabled));
}

/// A [ListenableProvider] that records its listenable in snoop's State tab.
///
/// Forwards every argument to [ListenableProvider] and tracks what `create`
/// (or `value`) returns with [SnoopListenable.track].
class SnoopListenableProvider<T extends Listenable?> extends ListenableProvider<T> {
  /// Creates a listenable with [create], tracks it and calls [dispose] when
  /// the provider leaves the tree, like [ListenableProvider].
  ///
  /// [name], [state] and [enabled] are those of [SnoopListenable.track].
  SnoopListenableProvider({
    required Create<T> create,
    super.key,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
    String? name,
    Object? Function(T notifier)? state,
    bool enabled = kDebugMode,
  }) : super(create: (context) => _tracked<T>(create(context), name, state, enabled));

  /// Provides and tracks an existing [value], like [ListenableProvider.value].
  SnoopListenableProvider.value({
    required T value,
    super.key,
    super.updateShouldNotify,
    super.builder,
    super.child,
    String? name,
    Object? Function(T notifier)? state,
    bool enabled = kDebugMode,
  }) : super.value(value: _tracked<T>(value, name, state, enabled));
}
