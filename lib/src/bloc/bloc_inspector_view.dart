import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:snoop/src/bloc/bloc_inspector_registry.dart';
import 'package:snoop/src/bloc/state_diff.dart';
import 'package:snoop/src/widgets/inspector_shared.dart';
import 'package:snoop/src/widgets/live_builder.dart';
import 'package:snoop/src/widgets/snoop_icon.dart';
import 'package:snoop/src/widgets/state_tree_view.dart';

/// The Bloc tab: a searchable list of live blocs and cubits. Tapping one
/// pushes its detail page: current state, last error and change history.
class BlocInspectorView extends StatelessWidget {
  /// Creates the view.
  const BlocInspectorView({required this.query, super.key});

  /// Search query owned by the panel header.
  final TextEditingController query;

  BlocInspectorRegistry get _registry => BlocInspectorRegistry.instance;

  @override
  Widget build(BuildContext context) => LiveBuilder(
    listenable: Listenable.merge(<Listenable>[_registry, query]),
    builder: (context) {
      if (_registry.count == 0) {
        return inspectorEmpty(
          'No live blocs',
          message:
              'A bloc shows up here when it is created and leaves when it closes. '
              'Open a screen that provides one.',
          icon: Icons.account_tree_outlined,
        );
      }
      final needle = query.text.trim().toLowerCase();
      final blocs = _registry.blocs
          .where((b) => needle.isEmpty || b.name.toLowerCase().contains(needle))
          .toList(growable: false);
      if (blocs.isEmpty) return inspectorNoMatches('No blocs match "$needle"');
      return ListView.builder(
        itemCount: blocs.length,
        itemBuilder: (context, i) => _BlocTile(
          tracked: blocs[i],
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => _BlocDetailPage(bloc: blocs[i].bloc))),
        ),
      );
    },
  );
}

class _BlocTile extends StatelessWidget {
  const _BlocTile({required this.tracked, required this.onTap});

  final TrackedBloc tracked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InspectorRow(
    onTap: onTap,
    leading: Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tracked.hasError ? InspectorColors.error : InspectorColors.success,
      ),
    ),
    title: Text(tracked.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: inspectorMeta(<String>[
      if (tracked.bloc is Bloc) 'bloc' else 'cubit',
      '${tracked.changeCount} changes',
      if (tracked.hasError) '${tracked.errorCount} errors',
    ]),
    trailing: tracked.hasError
        ? const Icon(Icons.error_outline, size: 16, color: InspectorColors.error)
        : null,
  );
}

class _BlocDetailPage extends StatefulWidget {
  const _BlocDetailPage({required this.bloc});

  final BlocBase<Object?> bloc;

  @override
  State<_BlocDetailPage> createState() => _BlocDetailPageState();
}

class _BlocDetailPageState extends State<_BlocDetailPage> {
  final TextEditingController _historyQuery = TextEditingController();
  late final Listenable _changes = Listenable.merge(<Listenable>[_registry, _historyQuery]);

  BlocInspectorRegistry get _registry => BlocInspectorRegistry.instance;

  @override
  void dispose() {
    _historyQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LiveBuilder(
    listenable: _changes,
    builder: (context) {
      final b = _registry[widget.bloc];
      if (b == null) {
        return InspectorDetailPage(
          title: 'Bloc',
          child: inspectorEmpty(
            'Bloc closed',
            message: 'This bloc closed while its page was open.',
            icon: Icons.account_tree_outlined,
          ),
        );
      }
      return InspectorDetailPage(
        title: b.name,
        actions: <Widget>[
          inspectorGlyph(
            icon: const SnoopIcon.copy(),
            tooltip: 'Copy current state',
            onTap: () => snoopCopy('${b.currentState}'),
          ),
        ],
        child: _body(b),
      );
    },
  );

  Widget _body(TrackedBloc b) {
    final needle = _historyQuery.text.trim().toLowerCase();
    final history = needle.isEmpty
        ? b.history
        : b.history.where((r) => '${r.event}'.toLowerCase().contains(needle)).toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        if (b.definedAt != null) inspectorSourceLine(const SnoopIcon.code(), b.definedAt!),
        const SizedBox(height: 8),
        inspectorField(
          'CURRENT STATE',
          copyValue: '${b.currentState}',
          child: StateTreeView(
            key: ValueKey<int>(Object.hash(identityHashCode(b.bloc), b.changeCount)),
            value: b.currentState,
          ),
        ),
        if (b.lastError != null) ...<Widget>[
          const SizedBox(height: 12),
          inspectorField(
            'LAST ERROR (${b.errorCount})',
            copyValue: '${b.lastError}\n${b.lastErrorStackTrace ?? ''}',
            child: SelectableText(
              '${b.lastError}',
              style: inspectorMono.copyWith(color: InspectorColors.error),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(child: inspectorLabel('HISTORY (${b.history.length})')),
            if (b.history.isNotEmpty)
              inspectorTextAction(
                'Clear',
                const SnoopIcon.trash(),
                () => _registry.clearHistory(b.bloc),
              ),
          ],
        ),
        if (b.history.any((r) => r.event != null)) ...<Widget>[
          InspectorSearchField(controller: _historyQuery, hint: 'Filter by event'),
          const SizedBox(height: 8),
        ],
        if (history.isEmpty)
          inspectorNoMatches(b.history.isEmpty ? 'No changes yet' : 'No events match "$needle"')
        else
          for (final r in history) _HistoryTile(record: r),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record});

  final BlocChangeRecord record;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: InspectorColors.card, borderRadius: BorderRadius.circular(6)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          inspectorTime(record.timestamp),
          style: const TextStyle(color: Colors.white38, fontSize: 9),
        ),
        if (record.event != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            '▸ ${record.event}',
            style: const TextStyle(color: InspectorColors.event, fontSize: 11),
          ),
        ],
        if (record.emittedFrom != null)
          inspectorSourceLine(const Icon(Icons.north_east), record.emittedFrom!),
        const SizedBox(height: 4),
        _DiffLines(changes: _diffOf(record)),
        const SizedBox(height: 2),
        StateTreeView(value: record.nextState, rootLabel: 'next', initiallyExpanded: false),
        StateTreeView(value: record.currentState, rootLabel: 'prev', initiallyExpanded: false),
      ],
    ),
  );
}

/// Diffs are computed once per record: the detail page rebuilds on every
/// change of any bloc, and records never change.
final Expando<List<StateChange>> _diffs = Expando<List<StateChange>>('snoop.diff');

List<StateChange> _diffOf(BlocChangeRecord r) =>
    _diffs[r] ??= diffStates(r.currentState, r.nextState);

/// What changed between `prev` and `next`, one line per field: `~` changed,
/// `+` added, `-` removed. Long lists collapse behind a "more" toggle.
class _DiffLines extends StatefulWidget {
  const _DiffLines({required this.changes});

  final List<StateChange> changes;

  @override
  State<_DiffLines> createState() => _DiffLinesState();
}

class _DiffLinesState extends State<_DiffLines> {
  static const int _collapsed = 6;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final changes = widget.changes;
    if (changes.isEmpty) {
      return const Text(
        'No field changed (an equal state was emitted)',
        style: TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic),
      );
    }
    final shown = _showAll ? changes : changes.take(_collapsed);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: InspectorColors.sunken,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final c in shown) _line(c),
          if (changes.length > _collapsed)
            GestureDetector(
              onTap: () => setState(() => _showAll = !_showAll),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _showAll ? 'Show less' : '+${changes.length - _collapsed} more',
                  style: TextStyle(color: InspectorColors.accentOf(context), fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _line(StateChange c) {
    final (String sign, Color color) = switch (c.kind) {
      StateChangeKind.changed => ('~', InspectorColors.warning),
      StateChangeKind.added => ('+', InspectorColors.success),
      StateChangeKind.removed => ('-', InspectorColors.error),
    };
    final style = inspectorMono.copyWith(fontSize: 10);
    return GestureDetector(
      onLongPress: () => snoopCopy('$c'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Text.rich(
          TextSpan(
            children: <TextSpan>[
              TextSpan(
                text: '$sign ',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
              TextSpan(
                text: c.path.isEmpty ? '(state)' : c.path,
                style: TextStyle(color: color),
              ),
              const TextSpan(text: '  '),
              ...switch (c.kind) {
                StateChangeKind.changed => <TextSpan>[
                  TextSpan(
                    text: _preview(c.before),
                    style: const TextStyle(color: Colors.white38),
                  ),
                  const TextSpan(
                    text: ' → ',
                    style: TextStyle(color: Colors.white38),
                  ),
                  TextSpan(text: _preview(c.after)),
                ],
                StateChangeKind.added => <TextSpan>[TextSpan(text: _preview(c.after))],
                StateChangeKind.removed => <TextSpan>[
                  TextSpan(
                    text: _preview(c.before),
                    style: const TextStyle(color: Colors.white38),
                  ),
                ],
              },
            ],
          ),
          style: style,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// A one-line rendering: strings quoted, collections as their size,
  /// objects as their type unless their text says more.
  static String _preview(Object? v) {
    final text = switch (v) {
      String() => '"$v"',
      Map() => '{…${v.length}}',
      Iterable() => '[…${v.length}]',
      null || num() || bool() || Enum() => '$v',
      _ when '$v'.startsWith("Instance of '") => '${v.runtimeType}',
      _ => '$v',
    };
    return text.length <= 80 ? text : '${text.substring(0, 79)}…';
  }
}
