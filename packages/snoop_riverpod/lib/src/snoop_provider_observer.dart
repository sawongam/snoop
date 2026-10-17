import 'package:flutter/foundation.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod/misc.dart' show ProviderBase;
import 'package:riverpod/riverpod.dart';
import 'package:snoop/snoop.dart';

/// A [ProviderObserver] that streams every provider lifecycle event into
/// `Snoop.state` for the inspector overlay.
///
/// ```dart
/// runApp(ProviderScope(observers: [SnoopProviderObserver()], child: const App()));
/// ```
///
/// Recording is on only when [enabled] is true, which defaults to
/// [kDebugMode]. In release builds the observer does nothing, so you can
/// install it unconditionally. Riverpod supports a list of observers, so
/// this one sits next to any you already have.
///
/// Each provider of each container is its own source: two `ProviderScope`s
/// with overrides show up separately, tagged `#1`, `#2`… in their details.
/// Family members are one source per argument, named `todo(1)`, `todo(2)`.
final class SnoopProviderObserver extends ProviderObserver {
  /// Creates the observer.
  ///
  /// * [captureCallSites] records where each provider was first read and
  ///   where each update was triggered from. It costs one stack capture per
  ///   provider and per update.
  /// * [shouldTrack] filters providers: return false to leave one out. By
  ///   default every provider is tracked.
  /// * [ignoredLocations] are extra location prefixes skipped when
  ///   resolving call sites, on top of [SnoopCallSite.ignored].
  SnoopProviderObserver({
    this.enabled = kDebugMode,
    this.captureCallSites = true,
    this.shouldTrack,
    List<String> ignoredLocations = const <String>[],
  }) : _extraIgnored = List<String>.unmodifiable(ignoredLocations) {
    if (enabled) {
      SnoopAdapters.register('riverpod', SnoopAdapterKind.state, ignoredLocations: _ignored);
      _registerAsyncValue();
    }
  }

  static const List<String> _ignored = <String>[
    'package:flutter_riverpod/',
    'package:hooks_riverpod/',
    'package:riverpod/',
    'package:riverpod_annotation/',
    'package:state_notifier/',
  ];

  static bool _asyncValueRegistered = false;

  /// Shows an `AsyncValue` as its status, value and error instead of an
  /// opaque object. Registered once.
  static void _registerAsyncValue() {
    if (_asyncValueRegistered) return;
    _asyncValueRegistered = true;
    SnoopStateTree.registerChildren((value) => value is AsyncValue<Object?>, (value) {
      final async = value as AsyncValue<Object?>;
      return <MapEntry<String, Object?>>[
        MapEntry<String, Object?>('status', _status(async)),
        MapEntry<String, Object?>('value', async.value),
        MapEntry<String, Object?>('error', async.error),
        MapEntry<String, Object?>('isRefreshing', async.isRefreshing),
        MapEntry<String, Object?>('isReloading', async.isReloading),
      ];
    });
  }

  static String _status(AsyncValue<Object?> value) => switch (value) {
    AsyncLoading<Object?>() => 'loading',
    AsyncData<Object?>() => 'data',
    AsyncError<Object?>() => 'error',
  };

  /// Whether anything is recorded.
  final bool enabled;

  /// Whether first-read and update sites are resolved from the stack.
  final bool captureCallSites;

  /// Decides whether a provider is shown. `null` shows every provider.
  final bool Function(ProviderBase<Object?> provider)? shouldTrack;

  final List<String> _extraIgnored;

  /// Container numbers and the keys each container owns. Weak on the
  /// container, so snoop never keeps a leaked container alive through here.
  final Expando<_ContainerInfo> _containers = Expando<_ContainerInfo>('snoop.riverpod');
  int _containerSeq = 0;

  _ContainerInfo _info(ProviderContainer container) =>
      _containers[container] ??= _ContainerInfo(++_containerSeq);

  String? _callSite() => captureCallSites ? SnoopCallSite.resolve(extra: _extraIgnored) : null;

  bool _tracks(ProviderBase<Object?> provider) {
    final filter = shouldTrack;
    return filter == null || (SnoopSafe.run(() => filter(provider)) ?? true);
  }

  /// Runs [body] when recording, swallowing anything it throws: this code
  /// runs inside the user's observer list.
  void _record(void Function() body) {
    if (!enabled) return;
    try {
      body();
    } on Object {
      // Never break the host app.
    }
  }

  /// Tracks the provider of [context] if it isn't yet and returns its key,
  /// or `null` when [shouldTrack] leaves it out.
  SnoopStateKey? _track(ProviderObserverContext context, {Object? value, bool first = false}) {
    final provider = context.provider;
    if (!_tracks(provider)) return null;
    final key = SnoopStateKey(context.container, provider);
    if (Snoop.state[key] != null) return key;
    final info = _info(context.container);
    final site = first ? _callSite() : null;
    Snoop.state.track(
      key,
      name: _name(provider),
      kind: _kind(provider),
      library: 'riverpod',
      initialState: value,
      details: <String, Object?>{
        'container': '#${info.number}',
        if (provider.from != null) 'argument': SnoopSafe.string(provider.argument, max: 200),
        if (provider.isAutoDispose) 'autoDispose': true,
        'firstReadAt': ?site,
      },
    );
    info.keys.add(key);
    return key;
  }

  @override
  void didCreateProviderContainer(ProviderContainer container) {
    _record(() => _info(container));
  }

  @override
  void didDisposeProviderContainer(ProviderContainer container) {
    _record(() {
      final info = _containers[container];
      if (info == null) return;
      for (final key in info.keys) {
        Snoop.state.markDisposed(key);
      }
      info.keys.clear();
    });
  }

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    _record(() => _track(context, value: value, first: true));
  }

  @override
  void didUpdateProvider(ProviderObserverContext context, Object? previousValue, Object? newValue) {
    _record(() {
      final key = _track(context, value: previousValue);
      if (key == null) return;
      Snoop.state
        ..noteEventOrigin(key, _callSite())
        ..change(key, previousValue, newValue, event: _mutationEvent(context.mutation));
    });
  }

  @override
  void providerDidFail(ProviderObserverContext context, Object error, StackTrace stackTrace) {
    _record(() {
      final key = _track(context);
      if (key != null) Snoop.state.error(key, error, stackTrace);
    });
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    _record(() {
      // Only `ref.onDispose` ran: the provider may rebuild right after, so
      // the source stays alive and just gets a marker in its history.
      final key = SnoopStateKey(context.container, context.provider);
      final source = Snoop.state[key];
      if (source == null) return;
      Snoop.state.change(
        key,
        source.currentState,
        source.currentState,
        event: 'disposed (ref.onDispose)',
      );
    });
  }

  @override
  void didUnmountProvider(ProviderObserverContext context) {
    _record(() {
      final key = SnoopStateKey(context.container, context.provider);
      Snoop.state.markDisposed(key);
      _containers[context.container]?.keys.remove(key);
    });
  }

  void _mutation(
    ProviderObserverContext context,
    Mutation<Object?> mutation,
    String event, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _record(() {
      final key = SnoopStateKey(context.container, mutation);
      if (Snoop.state[key] == null) {
        final info = _info(context.container);
        Snoop.state.track(
          key,
          name: _mutationName(mutation),
          kind: 'mutation',
          library: 'riverpod',
          hasState: false,
          details: <String, Object?>{'container': '#${info.number}'},
        );
        info.keys.add(key);
      }
      Snoop.state
        ..noteEventOrigin(key, _callSite())
        ..change(key, null, null, event: event);
      if (error != null) Snoop.state.error(key, error, stackTrace);
    });
  }

  @override
  void mutationStart(ProviderObserverContext context, Mutation<Object?> mutation) =>
      _mutation(context, mutation, 'started');

  @override
  void mutationSuccess(
    ProviderObserverContext context,
    Mutation<Object?> mutation,
    Object? result,
  ) => _mutation(context, mutation, 'succeeded');

  @override
  void mutationError(
    ProviderObserverContext context,
    Mutation<Object?> mutation,
    Object error,
    StackTrace stackTrace,
  ) => _mutation(context, mutation, 'failed', error: error, stackTrace: stackTrace);

  @override
  void mutationReset(ProviderObserverContext context, Mutation<Object?> mutation) =>
      _mutation(context, mutation, 'reset');

  static String? _mutationEvent(Mutation<Object?>? mutation) =>
      mutation == null ? null : 'mutation ${_mutationName(mutation)}';

  static String _mutationName(Mutation<Object?> mutation) {
    final label = SnoopSafe.run(() => mutation.label);
    final key = SnoopSafe.run(() => mutation.key);
    final base = label == null ? 'mutation' : SnoopSafe.string(label, max: 40);
    return key == null ? base : '$base(${SnoopSafe.string(key, max: 40)})';
  }
}

/// The number of a container and the keys of the sources it owns, so they
/// can all be retired when it is disposed.
final class _ContainerInfo {
  _ContainerInfo(this.number);

  final int number;
  final Set<SnoopStateKey> keys = <SnoopStateKey>{};
}

/// The panel name of [provider]: its `name` (set by riverpod_generator) or
/// its type without generics, plus `(argument)` for a family member.
String _name(ProviderBase<Object?> provider) {
  final base = provider.name ?? _typeName(provider);
  if (provider.from == null) return base;
  return '$base(${SnoopSafe.string(provider.argument, max: 40)})';
}

String _typeName(Object provider) {
  final type = SnoopSafe.string(provider.runtimeType, max: 80);
  final generics = type.indexOf('<');
  return generics < 0 ? type : type.substring(0, generics);
}

/// A readable kind from the provider's runtime type: `$AsyncNotifierProvider`
/// becomes `async notifier`, with markers for families and auto-dispose.
String _kind(ProviderBase<Object?> provider) {
  var type = _typeName(provider);
  for (final prefix in const <String>[r'$', 'AutoDispose']) {
    if (type.startsWith(prefix)) type = type.substring(prefix.length);
  }
  for (final suffix in const <String>['Family', 'Impl', 'Provider']) {
    if (type.endsWith(suffix)) type = type.substring(0, type.length - suffix.length);
  }
  final words = type
      .replaceAllMapped(RegExp('(?<=[a-z])(?=[A-Z])'), (_) => ' ')
      .toLowerCase()
      .trim();
  final family = provider.from != null ? ' (family)' : '';
  final auto = provider.isAutoDispose ? ' · autoDispose' : '';
  return '${words.isEmpty ? 'provider' : words}$family$auto';
}
