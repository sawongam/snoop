import 'package:flutter/foundation.dart';
import 'package:snoop/src/safe.dart';
import 'package:snoop/src/widgets/state_tree_view.dart';

/// How one field differs between two states.
enum StateChangeKind {
  /// The field exists in both states with different values.
  changed,

  /// The field exists only in the newer state.
  added,

  /// The field exists only in the older state.
  removed,
}

/// One field that differs between two states, as found by [diffStates].
@immutable
class StateChange {
  /// Creates a change record.
  const StateChange({required this.path, required this.kind, this.before, this.after});

  /// Where the field sits, e.g. `user.name` or `items[2]`. Empty for the
  /// root, which happens when the state type itself changed.
  final String path;

  /// What happened to the field.
  final StateChangeKind kind;

  /// The value in the older state; `null` when [kind] is
  /// [StateChangeKind.added].
  final Object? before;

  /// The value in the newer state; `null` when [kind] is
  /// [StateChangeKind.removed].
  final Object? after;

  @override
  String toString() => switch (kind) {
    StateChangeKind.changed =>
      '~ ${_label(path)}: ${SnoopSafe.string(before)} → ${SnoopSafe.string(after)}',
    StateChangeKind.added => '+ ${_label(path)}: ${SnoopSafe.string(after)}',
    StateChangeKind.removed => '- ${_label(path)}: ${SnoopSafe.string(before)}',
  };

  static String _label(String path) => path.isEmpty ? '(state)' : path;
}

/// The fields that differ between [before] and [after], walked the same way
/// `StateTreeView` shows them: map keys, `toJson()` fields, list indices and
/// `Equatable` props.
///
/// When the two values are objects of different types (a sealed
/// `AuthLoading` becoming `AuthLoaded`) the root is reported as one change
/// rather than a field-by-field list, which would be noise. Stops after
/// [maxChanges] changes or [maxVisits] compared values, and doesn't descend
/// past [maxDepth]. Never throws, whatever the states' `==` or `toString`
/// do.
List<StateChange> diffStates(
  Object? before,
  Object? after, {
  int maxDepth = 8,
  int maxChanges = 50,
  int maxVisits = 10000,
}) {
  final changes = <StateChange>[];
  var visits = 0;

  void walk(String path, Object? a, Object? b, int depth) {
    if (changes.length >= maxChanges || visits++ >= maxVisits || identical(a, b)) return;
    final aChildren = depth >= maxDepth ? null : childrenOf(a);
    final bChildren = depth >= maxDepth ? null : childrenOf(b);
    if (aChildren == null || bChildren == null || !_sameShape(a, b)) {
      if (!_leafEquals(a, b)) {
        changes.add(StateChange(path: path, kind: StateChangeKind.changed, before: a, after: b));
      }
      return;
    }
    final aMap = <String, Object?>{for (final e in aChildren) e.key: e.value};
    final bMap = <String, Object?>{for (final e in bChildren) e.key: e.value};
    for (final MapEntry(:key, :value) in aMap.entries) {
      final child = _join(path, key);
      if (bMap.containsKey(key)) {
        walk(child, value, bMap[key], depth + 1);
      } else if (changes.length < maxChanges) {
        changes.add(StateChange(path: child, kind: StateChangeKind.removed, before: value));
      }
    }
    for (final MapEntry(:key, :value) in bMap.entries) {
      if (aMap.containsKey(key) || changes.length >= maxChanges) continue;
      changes.add(StateChange(path: _join(path, key), kind: StateChangeKind.added, after: value));
    }
  }

  walk('', before, after, 0);
  return changes;
}

/// Maps and lists compare by content whatever their concrete class; other
/// objects must be the same type to be compared field by field.
bool _sameShape(Object? a, Object? b) {
  if (a is Map) return b is Map;
  if (a is Iterable) return b is Iterable;
  return a.runtimeType == b.runtimeType;
}

/// Leaves compare with `==`, falling back to their text so two equal-looking
/// objects without an `==` override don't read as a change.
bool _leafEquals(Object? a, Object? b) {
  if (SnoopSafe.run(() => a == b) ?? false) return true;
  if (a.runtimeType != b.runtimeType) return false;
  if (a == null || a is num || a is bool || a is String || a is Enum) return false;
  final text = SnoopSafe.string(a);
  // A default toString says nothing about the contents.
  return !text.startsWith("Instance of '") && text == SnoopSafe.string(b);
}

String _join(String path, String key) {
  if (key.startsWith('[')) return '$path$key';
  return path.isEmpty ? key : '$path.$key';
}
