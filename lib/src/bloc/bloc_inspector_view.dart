import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:snoop/src/bloc/bloc_inspector_registry.dart';
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
        const SizedBox(height: 2),
        StateTreeView(value: record.nextState, rootLabel: 'next', initiallyExpanded: false),
        StateTreeView(value: record.currentState, rootLabel: 'prev', initiallyExpanded: false),
      ],
    ),
  );
}
