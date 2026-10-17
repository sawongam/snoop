import 'dart:math';

import 'package:flutter/foundation.dart';

/// What a call made to fail by [SnoopNetworkConditions] fails with.
enum SnoopFault {
  /// A connection error, as if the device were offline.
  offline,

  /// A receive timeout.
  timeout,

  /// HTTP 500 Internal Server Error.
  serverError,

  /// HTTP 503 Service Unavailable.
  unavailable,

  /// HTTP 401 Unauthorized, e.g. to exercise token refresh.
  unauthorized,

  /// HTTP 429 Too Many Requests.
  tooManyRequests;

  /// The HTTP status this fault answers with, or `null` for network-level
  /// faults that never reach a server.
  int? get statusCode => switch (this) {
    SnoopFault.offline || SnoopFault.timeout => null,
    SnoopFault.serverError => 500,
    SnoopFault.unavailable => 503,
    SnoopFault.unauthorized => 401,
    SnoopFault.tooManyRequests => 429,
  };

  /// A short label for the picker and the call list.
  String get label => switch (this) {
    SnoopFault.offline => 'Offline',
    SnoopFault.timeout => 'Timeout',
    _ => '$statusCode',
  };
}

/// What a network adapter does to one call, from
/// [SnoopNetworkConditions.simulate].
@immutable
class SnoopSimulation {
  /// Creates a simulation.
  const SnoopSimulation({required this.delay, this.fault});

  /// Wait this long before sending (or failing) the call.
  final Duration delay;

  /// Fail the call with this instead of sending it, or `null` to send it.
  final SnoopFault? fault;
}

/// Simulated network trouble applied by every network adapter: extra
/// latency and a share of calls that fail on purpose. Set from the panel's
/// Network conditions page, or from code:
///
/// ```dart
/// Snoop.networkConditions
///   ..delay = const Duration(seconds: 2)
///   ..failureRate = 0.3
///   ..fault = SnoopFault.serverError
///   ..urlFilter = '/orders';
/// ```
///
/// Only calls an enabled adapter records are affected, so release builds
/// never see it. Nothing is persisted: a restart turns it all off.
class SnoopNetworkConditions extends ChangeNotifier {
  SnoopNetworkConditions._();

  /// The shared conditions.
  static final SnoopNetworkConditions instance = SnoopNetworkConditions._();

  Duration _delay = Duration.zero;
  double _failureRate = 0;
  SnoopFault _fault = SnoopFault.serverError;
  String _urlFilter = '';
  Random _random = Random();

  /// Added before every affected request is sent.
  Duration get delay => _delay;
  set delay(Duration value) => _set(() => _delay = value);

  /// Share of affected calls, from `0` to `1`, that fail with [fault]
  /// instead of reaching the server.
  double get failureRate => _failureRate;
  set failureRate(double value) => _set(() => _failureRate = value.clamp(0, 1));

  /// What failing calls fail with.
  SnoopFault get fault => _fault;
  set fault(SnoopFault value) => _set(() => _fault = value);

  /// Only calls whose URL contains this text (case-insensitive) are
  /// affected. Empty affects every call.
  String get urlFilter => _urlFilter;
  set urlFilter(String value) => _set(() => _urlFilter = value.trim());

  /// Whether anything is being simulated.
  bool get isActive => _delay > Duration.zero || _failureRate > 0;

  /// A one-line summary, e.g. `+2s · 30% fail with 500 · /orders`, or `null`
  /// when nothing is simulated.
  String? get summary {
    if (!isActive) return null;
    return <String>[
      if (_delay > Duration.zero) '+${_readable(_delay)}',
      if (_failureRate > 0) '${(_failureRate * 100).round()}% fail with ${_fault.label}',
      if (_urlFilter.isNotEmpty) _urlFilter,
    ].join('  ·  ');
  }

  /// Whether a call to [uri] is affected.
  bool appliesTo(Uri uri) =>
      isActive && (_urlFilter.isEmpty || '$uri'.toLowerCase().contains(_urlFilter.toLowerCase()));

  /// Rolls whether the next affected call fails.
  bool rollFailure() => _failureRate > 0 && _random.nextDouble() < _failureRate;

  /// What to do with a call to [uri], or `null` when nothing applies.
  ///
  /// Rolls the failure dice once, so call it exactly once per call. Each
  /// adapter turns [SnoopSimulation.fault] into its client's native error or
  /// response.
  SnoopSimulation? simulate(Uri uri) {
    if (!appliesTo(uri)) return null;
    final fault = rollFailure() ? _fault : null;
    if (fault == null && _delay == Duration.zero) return null;
    return SnoopSimulation(delay: _delay, fault: fault);
  }

  /// Turns every simulation off.
  void reset() => _set(() {
    _delay = Duration.zero;
    _failureRate = 0;
    _fault = SnoopFault.serverError;
    _urlFilter = '';
  });

  /// Replaces the random source, for deterministic tests.
  @visibleForTesting
  set random(Random value) => _random = value;

  void _set(VoidCallback change) {
    change();
    notifyListeners();
  }

  static String _readable(Duration d) =>
      d.inMilliseconds % 1000 == 0 ? '${d.inSeconds}s' : '${d.inMilliseconds}ms';
}
