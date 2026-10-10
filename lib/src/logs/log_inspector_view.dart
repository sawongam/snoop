import 'package:flutter/material.dart';
import 'package:snoop/src/logs/log_inspector_registry.dart';
import 'package:snoop/src/widgets/inspector_shared.dart';
import 'package:snoop/src/widgets/live_builder.dart';

/// The Logs tab: recorded log lines, searchable across message, source and
/// error. Tap a line to expand its error and stack trace; long-press to copy.
class LogInspectorView extends StatefulWidget {
  /// Creates the view.
  const LogInspectorView({required this.query, super.key});

  /// Search query owned by the panel header.
  final TextEditingController query;

  @override
  State<LogInspectorView> createState() => _LogInspectorViewState();
}

class _LogInspectorViewState extends State<LogInspectorView> {
  late final Listenable _changes = Listenable.merge(<Listenable>[_registry, widget.query]);

  /// Expanded lines, by identity so the expansion survives new lines arriving
  /// on top.
  final Set<SnoopLogRecord> _expanded = Set<SnoopLogRecord>.identity();

  LogInspectorRegistry get _registry => LogInspectorRegistry.instance;

  @override
  Widget build(BuildContext context) => LiveBuilder(
    listenable: _changes,
    builder: (context) {
      final records = _registry.records;
      if (records.isEmpty) {
        return inspectorEmpty(
          'Nothing logged yet',
          message: 'Feed your logger into Snoop.logs.log(…) to keep lines here.',
          icon: Icons.notes_rounded,
        );
      }
      final query = widget.query.text.trim().toLowerCase();
      final visible = records.where((r) => r.matches(query)).toList(growable: false);
      if (visible.isEmpty) return inspectorNoMatches('No lines match "$query"');
      return ListView.builder(
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final record = visible[i];
          final expanded = _expanded.contains(record);
          return _LogTile(
            record: record,
            expanded: expanded,
            onTap: () => setState(() {
              if (!_expanded.remove(record)) _expanded.add(record);
            }),
          );
        },
      );
    },
  );
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.record, required this.expanded, required this.onTap});

  final SnoopLogRecord record;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final error = record.error;
    final trace = record.stackTrace;
    return InspectorRow(
      onTap: onTap,
      onLongPress: () => snoopCopy(record.text),
      showChevron: false,
      leading: _LevelTag(level: record.level),
      title: Text(
        record.message,
        maxLines: expanded ? null : 2,
        overflow: expanded ? null : TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          inspectorMeta(<String>[inspectorTime(record.timestamp), ?record.source]),
          if (expanded && (error != null || trace != null)) ...<Widget>[
            const SizedBox(height: 4),
            inspectorBox(
              child: SelectableText(
                <String>[
                  if (error != null && '$error' != record.message) '$error',
                  if (trace != null) '$trace',
                ].join('\n'),
                style: inspectorMono.copyWith(fontSize: 10, color: Colors.white70),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LevelTag extends StatelessWidget {
  const _LevelTag({required this.level});

  final SnoopLogLevel level;

  @override
  Widget build(BuildContext context) => InspectorTag(
    switch (level) {
      SnoopLogLevel.debug => 'DBG',
      SnoopLogLevel.info => 'INF',
      SnoopLogLevel.warning => 'WRN',
      SnoopLogLevel.error => 'ERR',
      SnoopLogLevel.fatal => 'FTL',
    },
    color: switch (level) {
      SnoopLogLevel.debug => Colors.white54,
      SnoopLogLevel.info => InspectorColors.info,
      SnoopLogLevel.warning => InspectorColors.warning,
      SnoopLogLevel.error || SnoopLogLevel.fatal => InspectorColors.error,
    },
  );
}
