import 'package:flutter/material.dart';
import 'package:snoop/src/widgets/inspector_shared.dart';
import 'package:snoop/src/widgets/snoop_icon.dart';
import 'package:snoop/src/widgets/state_tree_view.dart';

/// Shows [value] in a dark bottom sheet as an expandable tree, with the raw
/// pretty-printed JSON one tap away, and a copy button.
///
/// Useful outside the inspector too: put it behind a long-press while
/// building a screen, and the DTO that actually arrived is one gesture away.
///
/// ```dart
/// onLongPress: () => showValueSheet(context: context, title: 'Post', value: post),
/// ```
///
/// [value] can be anything [StateTreeView] can render: a `Map`, an
/// `Iterable`, an object with `toJson()` or Equatable `props`. Needs a
/// [Navigator] above [context].
Future<void> showValueSheet({
  required BuildContext context,
  required String title,
  required Object? value,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: InspectorColors.panel,
  clipBehavior: Clip.antiAlias,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
  ),
  builder: (_) => Theme(
    data: inspectorTheme(Theme.of(context).colorScheme.primary),
    child: FractionallySizedBox(
      heightFactor: 0.85,
      child: _ValueSheetBody(title: title, value: value),
    ),
  ),
);

class _ValueSheetBody extends StatefulWidget {
  const _ValueSheetBody({required this.title, required this.value});

  final String title;
  final Object? value;

  @override
  State<_ValueSheetBody> createState() => _ValueSheetBodyState();
}

class _ValueSheetBodyState extends State<_ValueSheetBody> {
  late final String _pretty = inspectorPretty(widget.value);
  bool _raw = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            InspectorSegmented<bool>(
              value: _raw,
              segments: const <(bool, String)>[(false, 'Tree'), (true, 'Raw')],
              onChanged: (raw) => setState(() => _raw = raw),
            ),
            inspectorGlyph(
              icon: const SnoopIcon.copy(),
              tooltip: 'Copy as JSON',
              onTap: () => snoopCopy(_pretty),
            ),
            inspectorGlyph(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
      const Divider(height: 1, color: InspectorColors.divider),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: inspectorBox(
            child: _raw
                ? SelectableText(_pretty, style: inspectorMono.copyWith(height: 1.4))
                : StateTreeView(value: widget.value),
          ),
        ),
      ),
    ],
  );
}
