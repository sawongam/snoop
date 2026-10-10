import 'package:flutter/material.dart';
import 'package:snoop/src/widgets/inspector_shared.dart';

/// A lazily expandable, JSON-style tree for inspecting any value.
///
/// Children come from the richest source the value exposes:
/// - a `Map`: its keys;
/// - anything with a `toJson()` returning a `Map` (most DTOs): field names;
/// - an `Iterable`: `[i]` indices;
/// - anything with a `props` list (`Equatable` states): `[i]` over `props`.
///
/// Primitives and enums render as colored leaves. Children are computed only
/// once per value and nodes build lazily, so deep graphs stay cheap until you
/// drill in. Long-press a node to copy its value.
class StateTreeView extends StatelessWidget {
  /// Creates a tree for [value].
  const StateTreeView({
    required this.value,
    this.rootLabel,
    this.initiallyExpanded = true,
    this.maxDepth = 8,
    super.key,
  });

  /// The value to show.
  final Object? value;

  /// Optional label shown before the root value.
  final String? rootLabel;

  /// Whether the root node starts expanded.
  final bool initiallyExpanded;

  /// Nodes deeper than this are shown as leaves.
  final int maxDepth;

  @override
  Widget build(BuildContext context) => _TreeNode(
    label: rootLabel,
    value: value,
    depth: 0,
    maxDepth: maxDepth,
    initiallyExpanded: initiallyExpanded,
  );
}

const Color _keyColor = InspectorColors.accent;
const Color _stringColor = InspectorColors.success;
const Color _numColor = InspectorColors.event;
const Color _boolColor = Color(0xFFF472B6);
const Color _enumColor = Color(0xFF38BDF8);
const Color _typeColor = Color(0xFF94A3B8);

List<MapEntry<String, Object?>> _entries(Map<Object?, Object?> map) => <MapEntry<String, Object?>>[
  for (final e in map.entries) MapEntry('${e.key}', e.value),
];

List<MapEntry<String, Object?>> _indexed(Iterable<Object?> items) => <MapEntry<String, Object?>>[
  for (final (i, item) in items.indexed) MapEntry('[$i]', item),
];

/// The named or indexed children of [v], or `null` if it is a leaf.
List<MapEntry<String, Object?>>? childrenOf(Object? v) {
  if (v == null || v is num || v is bool || v is String || v is Enum) return null;
  if (v is Map) return _entries(v);
  if (v is Iterable) return _indexed(v);
  // Duck-type toJson() and props so no serialization or equatable dependency
  // is needed. Either may be absent or throw.
  try {
    // ignore: avoid_dynamic_calls
    final json = (v as dynamic).toJson();
    if (json is Map) return _entries(json);
  } on Object {
    // No usable toJson(); fall through.
  }
  try {
    // ignore: avoid_dynamic_calls
    final props = (v as dynamic).props;
    if (props is List) return _indexed(props);
  } on Object {
    // No props; it's a leaf.
  }
  return null;
}

class _TreeNode extends StatefulWidget {
  const _TreeNode({
    required this.value,
    required this.depth,
    required this.maxDepth,
    this.label,
    this.initiallyExpanded = false,
  });

  final String? label;
  final Object? value;
  final int depth;
  final int maxDepth;
  final bool initiallyExpanded;

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  late bool _expanded = widget.initiallyExpanded;
  late List<MapEntry<String, Object?>>? _children = _resolve();

  List<MapEntry<String, Object?>>? _resolve() =>
      widget.depth >= widget.maxDepth ? null : childrenOf(widget.value);

  @override
  void didUpdateWidget(_TreeNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value)) _children = _resolve();
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    final expandable = children != null && children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        InkWell(
          onTap: expandable ? () => setState(() => _expanded = !_expanded) : null,
          onLongPress: () => snoopCopy(_copyable(widget.value)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 16,
                  child: expandable
                      ? Icon(
                          _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                          size: 14,
                          color: Colors.white54,
                        )
                      : null,
                ),
                Expanded(child: _header(children)),
              ],
            ),
          ),
        ),
        if (expandable && _expanded)
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final child in children)
                  _TreeNode(
                    label: child.key,
                    value: child.value,
                    depth: widget.depth + 1,
                    maxDepth: widget.maxDepth,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// A JSON-encodable form of [v] for copying: maps and lists as-is, objects
  /// via their resolved children.
  static Object? _copyable(Object? v) {
    if (v == null || v is num || v is bool || v is String || v is Map || v is List) return v;
    if (v is Enum) return '$v';
    final children = childrenOf(v);
    if (children == null) return '$v';
    return <String, Object?>{for (final c in children) c.key: _copyable(c.value)};
  }

  Widget _header(List<MapEntry<String, Object?>>? children) => Text.rich(
    TextSpan(
      children: <TextSpan>[
        if (widget.label != null)
          TextSpan(
            text: '${widget.label}: ',
            style: const TextStyle(color: _keyColor, fontWeight: FontWeight.w600),
          ),
        if (children != null && children.isNotEmpty)
          TextSpan(text: _typeLabel(widget.value, children.length), style: _type)
        else
          _leaf(widget.value),
      ],
    ),
    style: inspectorMono.copyWith(height: 1.4),
  );

  static const TextStyle _type = TextStyle(color: _typeColor);

  static String _typeLabel(Object? v, int count) => switch (v) {
    Map() => '{…} $count',
    Iterable() => '[…] $count',
    _ => '${v.runtimeType}',
  };

  static TextSpan _leaf(Object? v) => switch (v) {
    null => const TextSpan(
      text: 'null',
      style: TextStyle(color: _boolColor),
    ),
    String() => TextSpan(
      text: '"$v"',
      style: const TextStyle(color: _stringColor),
    ),
    num() => TextSpan(
      text: '$v',
      style: const TextStyle(color: _numColor),
    ),
    bool() => TextSpan(
      text: '$v',
      style: const TextStyle(color: _boolColor),
    ),
    Enum() => TextSpan(
      text: '$v',
      style: const TextStyle(color: _enumColor),
    ),
    Map() => const TextSpan(text: '{}', style: _type),
    Iterable() => const TextSpan(text: '[]', style: _type),
    // A default toString reads "Instance of 'Foo'". Show the type and a hint
    // instead, so it's clear the class just lacks a toJson/props hook.
    _ when '$v'.startsWith("Instance of '") => TextSpan(
      text: '${v.runtimeType}  (no toJson/props)',
      style: const TextStyle(color: _typeColor, fontStyle: FontStyle.italic),
    ),
    _ => TextSpan(
      text: '$v',
      style: const TextStyle(color: Colors.white70),
    ),
  };
}
