import 'package:flutter/material.dart';
import 'package:snoop/src/safe.dart';
import 'package:snoop/src/state/state_diff.dart';
import 'package:snoop/src/state/state_registry.dart';
import 'package:snoop/src/widgets/inspector_shared.dart';
import 'package:snoop/src/widgets/live_builder.dart';
import 'package:snoop/src/widgets/snoop_icon.dart';
import 'package:snoop/src/widgets/state_tree_view.dart';

/// The State tab: a searchable list of live state sources (blocs, providers,
/// signals…), then the recently disposed ones. Tapping one pushes its detail
/// page: details, current state, last error and change history.
class StateInspectorView extends StatefulWidget {
  /// Creates the view.
  const StateInspectorView({required this.query, super.key});

  /// Search query owned by the panel header.
  final TextEditingController query;

  @override
  State<StateInspectorView> createState() => _StateInspectorViewState();
}

class _StateInspectorViewState extends State<StateInspectorView> {
  late final Listenable _changes = Listenable.merge(<Listenable>[_registry, widget.query]);
  bool _showDisposed = false;

  SnoopStateRegistry get _registry => SnoopStateRegistry.instance;

  void _open(BuildContext context, SnoopStateSource source) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => _SourceDetailPage(id: source.id)));

  @override
  Widget build(BuildContext context) => LiveBuilder(
    listenable: _changes,
    builder: (context) {
      final all = _registry.sources;
      if (all.isEmpty) {
        return inspectorEmpty(
          'No live state',
          message:
              'A bloc, provider, store or signal shows up here once its snoop adapter sees '
              'it. Open a screen that creates one.',
          icon: Icons.account_tree_outlined,
        );
      }
      final needle = widget.query.text.trim().toLowerCase();
      final live = _registry.live.where((s) => s.matches(needle)).toList(growable: false);
      final disposed = _registry.disposed.where((s) => s.matches(needle)).toList(growable: false);
      if (live.isEmpty && disposed.isEmpty) return inspectorNoMatches('Nothing matches "$needle"');
      final showLibrary = _registry.libraries.length > 1;
      return ListView(
        children: <Widget>[
          for (final s in live)
            _SourceTile(source: s, showLibrary: showLibrary, onTap: () => _open(context, s)),
          if (disposed.isNotEmpty) ...<Widget>[
            InkWell(
              key: const ValueKey<String>('snoop.disposed'),
              onTap: () => setState(() => _showDisposed = !_showDisposed),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _showDisposed ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: inspectorLabel('DISPOSED (${disposed.length})')),
                  ],
                ),
              ),
            ),
            if (_showDisposed)
              for (final s in disposed)
                _SourceTile(source: s, showLibrary: showLibrary, onTap: () => _open(context, s)),
          ],
        ],
      );
    },
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source, required this.showLibrary, required this.onTap});

  final SnoopStateSource source;
  final bool showLibrary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tile = InspectorRow(
      onTap: onTap,
      leading: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: source.isDisposed
              ? Colors.white24
              : source.hasError
              ? InspectorColors.error
              : InspectorColors.success,
        ),
      ),
      title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: inspectorMeta(<String>[
        source.kind,
        if (showLibrary) source.library,
        if (source.hasState || source.changeCount > 0)
          '${source.changeCount} ${source.hasState ? 'changes' : 'runs'}',
        if (source.hasError) '${source.errorCount} errors',
        if (source.disposedAt != null) 'disposed ${inspectorTime(source.disposedAt!)}',
      ]),
      trailing: source.hasError
          ? const Icon(Icons.error_outline, size: 16, color: InspectorColors.error)
          : null,
    );
    return source.isDisposed ? Opacity(opacity: 0.55, child: tile) : tile;
  }
}

class _SourceDetailPage extends StatefulWidget {
  const _SourceDetailPage({required this.id});

  final int id;

  @override
  State<_SourceDetailPage> createState() => _SourceDetailPageState();
}

class _SourceDetailPageState extends State<_SourceDetailPage> {
  final TextEditingController _historyQuery = TextEditingController();
  late final Listenable _changes = Listenable.merge(<Listenable>[_registry, _historyQuery]);

  SnoopStateRegistry get _registry => SnoopStateRegistry.instance;

  @override
  void dispose() {
    _historyQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LiveBuilder(
    listenable: _changes,
    builder: (context) {
      final s = _registry.byId(widget.id);
      if (s == null) {
        return InspectorDetailPage(
          title: 'State',
          child: inspectorEmpty(
            'Gone',
            message: 'It was cleared, or rolled off the recorder.',
            icon: Icons.account_tree_outlined,
          ),
        );
      }
      return InspectorDetailPage(
        title: s.name,
        actions: <Widget>[
          if (s.hasState)
            inspectorGlyph(
              icon: const SnoopIcon.copy(),
              tooltip: 'Copy current state',
              onTap: () => snoopCopy(jsonFriendly(s.currentState)),
            ),
        ],
        child: _body(s),
      );
    },
  );

  Widget _body(SnoopStateSource s) {
    final needle = _historyQuery.text.trim().toLowerCase();
    final history = needle.isEmpty
        ? s.history
        : s.history.where((r) => SnoopSafe.string(r.event).toLowerCase().contains(needle)).toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        inspectorMeta(<String>[
          s.kind,
          s.library,
          'since ${inspectorTime(s.createdAt)}',
          if (s.disposedAt != null) 'disposed ${inspectorTime(s.disposedAt!)}',
        ]),
        if (s.definedAt != null) inspectorSourceLine(const SnoopIcon.code(), s.definedAt!),
        if (s.details.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          for (final MapEntry(:key, :value) in s.details.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text.rich(
                TextSpan(
                  children: <TextSpan>[
                    TextSpan(
                      text: '$key  ',
                      style: const TextStyle(color: Colors.white38),
                    ),
                    TextSpan(text: SnoopSafe.string(value, max: 200)),
                  ],
                ),
                style: inspectorMono.copyWith(fontSize: 10),
              ),
            ),
        ],
        const SizedBox(height: 8),
        if (s.hasState)
          inspectorField(
            'CURRENT STATE',
            copyValue: jsonFriendly(s.currentState),
            child: StateTreeView(
              key: ValueKey<int>(Object.hash(s.id, s.changeCount)),
              value: s.currentState,
            ),
          ),
        if (s.lastError != null) ...<Widget>[
          const SizedBox(height: 12),
          inspectorField(
            'LAST ERROR (${s.errorCount})',
            copyValue: '${SnoopSafe.string(s.lastError)}\n${s.lastErrorStackTrace ?? ''}',
            child: SelectableText(
              SnoopSafe.string(s.lastError),
              style: inspectorMono.copyWith(color: InspectorColors.error),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(child: inspectorLabel('HISTORY (${s.history.length})')),
            if (s.history.isNotEmpty)
              inspectorTextAction(
                'Clear',
                const SnoopIcon.trash(),
                () => _registry.clearHistory(s),
              ),
          ],
        ),
        if (s.history.any((r) => r.event != null)) ...<Widget>[
          InspectorSearchField(controller: _historyQuery, hint: 'Filter by event'),
          const SizedBox(height: 8),
        ],
        if (history.isEmpty)
          inspectorNoMatches(s.history.isEmpty ? 'No changes yet' : 'No events match "$needle"')
        else
          for (final r in history) _HistoryTile(record: r, hasState: s.hasState),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record, required this.hasState});

  final SnoopStateChange record;
  final bool hasState;

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
            '▸ ${SnoopSafe.string(record.event, max: 300)}',
            style: const TextStyle(color: InspectorColors.event, fontSize: 11),
          ),
        ],
        if (record.emittedFrom != null)
          inspectorSourceLine(const Icon(Icons.north_east), record.emittedFrom!),
        if (hasState) ...<Widget>[
          const SizedBox(height: 4),
          if (record.hasPrevious)
            _DiffLines(changes: _diffOf(record))
          else
            const Text(
              'First value seen',
              style: TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic),
            ),
          const SizedBox(height: 2),
          StateTreeView(value: record.next, rootLabel: 'next', initiallyExpanded: false),
          if (record.hasPrevious)
            StateTreeView(value: record.previous, rootLabel: 'prev', initiallyExpanded: false),
        ],
      ],
    ),
  );
}

/// Diffs are computed once per record: the detail page rebuilds on every
/// change of any source, and records never change.
final Expando<List<StateChange>> _diffs = Expando<List<StateChange>>('snoop.diff');

List<StateChange> _diffOf(SnoopStateChange r) => _diffs[r] ??= diffStates(r.previous, r.next);

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
      _ when SnoopSafe.string(v).startsWith("Instance of '") => '${v.runtimeType}',
      _ => SnoopSafe.string(v, max: 200),
    };
    return text.length <= 80 ? text : '${text.substring(0, 79)}…';
  }
}
