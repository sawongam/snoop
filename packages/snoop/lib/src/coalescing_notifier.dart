import 'dart:async';

import 'package:flutter/foundation.dart';

/// A [ChangeNotifier] that coalesces bursts of changes into a single
/// notification, delivered in a microtask.
///
/// Blocs are often created and requests often resolve mid-build. Notifying
/// synchronously from there would trigger `setState() called during build`.
/// Deferring to a microtask avoids that, and it also batches many changes
/// (a chatty cubit, a burst of requests) into one rebuild of the inspector.
abstract class CoalescingNotifier extends ChangeNotifier {
  bool _scheduled = false;

  /// Schedules a single deferred [notifyListeners] call. Calls made before
  /// that notification runs are merged into it.
  @protected
  void scheduleNotify() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      notifyListeners();
    });
  }
}

/// A [CoalescingNotifier] holding a bounded, newest-first list of records.
///
/// Every recorder that keeps a ring of the last N events (calls, log lines,
/// navigations) shares this, so the cap, the insert and the clear are written
/// once.
abstract class InspectorHistory<T> extends CoalescingNotifier {
  final List<T> _records = <T>[];

  /// Maximum number of records kept. Older records are dropped.
  int maxRecords = 100;

  /// The records, newest first.
  List<T> get records => List<T>.unmodifiable(_records);

  /// Number of records held.
  int get count => _records.length;

  /// Whether nothing has been recorded.
  bool get isEmpty => _records.isEmpty;

  /// Records [record] as the newest entry, dropping the oldest over the cap.
  @protected
  void push(T record) {
    _records.insert(0, record);
    if (_records.length > maxRecords) _records.removeRange(maxRecords, _records.length);
    scheduleNotify();
  }

  /// Notifies listeners after an existing record was mutated in place.
  void changed() => scheduleNotify();

  /// Drops every record.
  void clear() {
    if (_records.isEmpty) return;
    _records.clear();
    scheduleNotify();
  }
}
