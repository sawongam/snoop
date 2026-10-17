import 'package:flutter/material.dart';
import 'package:snoop/src/network/network_conditions.dart';
import 'package:snoop/src/network/network_registry.dart';
import 'package:snoop/src/network/network_support.dart';
import 'package:snoop/src/network/network_tools.dart';
import 'package:snoop/src/widgets/inspector_shared.dart';
import 'package:snoop/src/widgets/live_builder.dart';
import 'package:snoop/src/widgets/snoop_icon.dart';
import 'package:snoop/src/widgets/state_tree_view.dart';

enum _Filter { all, errors, pending, cancelled }

/// Above this, a call's duration is drawn as slow.
const Duration _slowCall = Duration(seconds: 1);

/// The Network tab: a summary of every recorded call, then a filterable list.
/// Tapping a call pushes its detail page: URL, error, headers, payloads.
class NetworkInspectorView extends StatefulWidget {
  /// Creates the view.
  const NetworkInspectorView({required this.query, super.key});

  /// Search query owned by the panel header.
  final TextEditingController query;

  @override
  State<NetworkInspectorView> createState() => _NetworkInspectorViewState();
}

class _NetworkInspectorViewState extends State<NetworkInspectorView> {
  late final Listenable _changes = Listenable.merge(<Listenable>[
    _registry,
    widget.query,
    SnoopNetworkConditions.instance,
  ]);
  _Filter _filter = _Filter.all;
  bool _statsExpanded = false;

  SnoopNetworkRegistry get _registry => SnoopNetworkRegistry.instance;

  bool _passes(SnoopCallRecord r) => switch (_filter) {
    _Filter.all => true,
    _Filter.errors => r.isError,
    _Filter.pending => r.isPending,
    _Filter.cancelled => r.cancelled,
  };

  @override
  Widget build(BuildContext context) => LiveBuilder(
    listenable: _changes,
    builder: (context) {
      final records = _registry.records;
      if (records.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const NetworkConditionsBanner(),
            Expanded(
              child: inspectorEmpty(
                'No calls recorded',
                message:
                    'Every request through an HTTP client with a snoop adapter lands '
                    'here. Open a screen that loads data and come back.',
                icon: Icons.swap_vert_rounded,
              ),
            ),
            Center(
              child: inspectorTextAction(
                'Network conditions',
                const Icon(Icons.speed),
                () => openNetworkConditions(context),
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      }
      final query = widget.query.text.trim().toLowerCase();
      final visible = records.where((r) => _passes(r) && r.matches(query)).toList(growable: false);
      final showClient = _registry.clients.length > 1;
      return CustomScrollView(
        slivers: <Widget>[
          const SliverToBoxAdapter(child: NetworkConditionsBanner()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            sliver: SliverToBoxAdapter(
              child: _StatsCard(
                records: records,
                expanded: _statsExpanded,
                onToggle: () => setState(() => _statsExpanded = !_statsExpanded),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _filterBar(records)),
          if (visible.isEmpty)
            SliverToBoxAdapter(child: inspectorNoMatches('No calls match the filter'))
          else
            SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (context, i) => _CallTile(
                record: visible[i],
                showClient: showClient,
                onTap: () => openCall(context, visible[i].id),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 12)),
        ],
      );
    },
  );

  Widget _filterBar(List<SnoopCallRecord> records) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
    child: Row(
      children: <Widget>[
        // Scrolls rather than overflows on narrow phones or large text.
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: InspectorSegmented<_Filter>(
              value: _filter,
              segments: <(_Filter, String)>[
                (_Filter.all, 'All'),
                (_Filter.errors, 'Errors (${_registry.errorCount})'),
                (_Filter.pending, 'Pending'),
                if (_registry.cancelledCount > 0 || _filter == _Filter.cancelled)
                  (_Filter.cancelled, 'Cancelled'),
              ],
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
        ),
        inspectorGlyph(
          key: const ValueKey<String>('snoop.network_conditions'),
          icon: const Icon(Icons.speed),
          tooltip: 'Network conditions',
          active: SnoopNetworkConditions.instance.isActive,
          onTap: () => openNetworkConditions(context),
        ),
        inspectorGlyph(
          icon: const SnoopIcon.copy(),
          tooltip: 'Copy all as JSON',
          onTap: () => snoopCopy(<Object?>[for (final r in records) r.toJson()]),
        ),
      ],
    ),
  );
}

/// One summary line over the list, expanding into a per-endpoint table
/// sorted slowest first.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.records, required this.expanded, required this.onToggle});

  final List<SnoopCallRecord> records;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final stats = SnoopCallStats.of(records);
    return Material(
      color: InspectorColors.card,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: inspectorMeta(<String>[
                      '${stats.total} calls',
                      if (stats.errors > 0) '${stats.errors} failed',
                      if (stats.pending > 0) '${stats.pending} in flight',
                      if (stats.cancelled > 0) '${stats.cancelled} cancelled',
                      ?stats.readableStatus,
                      if (stats.p95Ms != null) 'p95 ${stats.p95Ms} ms',
                      ?stats.readableBytes,
                    ]),
                  ),
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: Colors.white38,
                  ),
                ],
              ),
              if (expanded) ...<Widget>[
                const SizedBox(height: 6),
                const Divider(height: 1, color: InspectorColors.divider),
                const SizedBox(height: 6),
                for (final row in SnoopEndpointStats.group(records))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            row.endpoint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: inspectorMono.copyWith(fontSize: 10, color: Colors.white70),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          <String>[
                            '×${row.stats.total}',
                            if (row.stats.p95Ms != null) '${row.stats.p95Ms}ms',
                            ?row.stats.endpointStatus,
                          ].join('  '),
                          style: TextStyle(
                            fontSize: 10,
                            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                            color: row.stats.errors > 0 ? InspectorColors.error : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.record, required this.showClient, required this.onTap});

  final SnoopCallRecord record;
  final bool showClient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = record.duration;
    return InspectorRow(
      onTap: onTap,
      leading: StatusBadge(record: record),
      title: Text.rich(
        TextSpan(
          children: <TextSpan>[
            TextSpan(
              text: '${record.method} ',
              style: TextStyle(
                color: InspectorColors.method(record.method),
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            TextSpan(text: record.path),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: inspectorMeta(<String>[
        if (showClient) record.client,
        record.uri.host,
        inspectorTime(record.startedAt),
        ?_tagOf(record),
      ]),
      trailing: duration == null
          ? null
          : Text(
              '${duration.inMilliseconds}ms',
              style: TextStyle(
                color: duration >= _slowCall ? InspectorColors.warning : Colors.white38,
                fontSize: 10,
              ),
            ),
    );
  }
}

/// `simulated 500` or `replay of #12`, for calls that need telling apart.
String? _tagOf(SnoopCallRecord r) {
  if (r.injectedFault != null) return 'simulated ${r.injectedFault!.label.toLowerCase()}';
  if (r.replayOf != null) return 'replay of #${r.replayOf}';
  if (r.retryOf != null) return 'retry of #${r.retryOf}';
  return null;
}

/// One call in full: URL, error, headers, payloads, and replay actions.
class NetworkCallDetailPage extends StatelessWidget {
  /// Creates the page for call [id].
  const NetworkCallDetailPage({required this.id, super.key});

  /// The call's [SnoopCallRecord.id].
  final int id;

  @override
  Widget build(BuildContext context) => LiveBuilder(
    listenable: SnoopNetworkRegistry.instance,
    builder: (context) {
      final r = SnoopNetworkRegistry.instance.records.where((r) => r.id == id).firstOrNull;
      if (r == null) {
        return InspectorDetailPage(
          title: 'Call',
          child: inspectorEmpty(
            'Call not found',
            message: 'It was cleared, or rolled off the recorder.',
            icon: Icons.swap_vert_rounded,
          ),
        );
      }
      return InspectorDetailPage(
        title: r.shortPath,
        actions: <Widget>[
          inspectorGlyph(
            icon: const Icon(Icons.terminal),
            tooltip: 'Copy as cURL',
            onTap: () => snoopCopy(buildCurl(r)),
          ),
          inspectorGlyph(
            icon: const SnoopIcon.copy(),
            tooltip: 'Copy call as JSON',
            onTap: () => snoopCopy(r.toJson()),
          ),
        ],
        child: _detail(r),
      );
    },
  );

  Widget _detail(SnoopCallRecord r) => ListView(
    padding: const EdgeInsets.all(12),
    children: <Widget>[
      Row(
        children: <Widget>[
          StatusBadge(record: r),
          const SizedBox(width: 8),
          Expanded(
            child: inspectorMeta(<String>[
              r.client,
              inspectorTime(r.startedAt),
              if (r.duration != null) '${r.duration!.inMilliseconds} ms',
              if (r.responseBytes != null) SnoopBody.readableSize(r.responseBytes!),
              if (r.cancelled) 'cancelled',
              if (r.errorType != null) r.errorType!,
              ?_tagOf(r),
            ]),
          ),
        ],
      ),
      const SizedBox(height: 4),
      ReplayActions(record: r),
      const SizedBox(height: 8),
      inspectorField(
        'URL',
        copyValue: r.uri.toString(),
        child: SelectableText(r.uri.toString(), style: inspectorMono),
      ),
      if (r.finalUri != null && r.finalUri != r.uri) ...<Widget>[
        const SizedBox(height: 12),
        inspectorField(
          'REDIRECTED TO',
          copyValue: r.finalUri.toString(),
          child: SelectableText(r.finalUri.toString(), style: inspectorMono),
        ),
      ],
      if (r.uri.queryParameters.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        _headers('QUERY PARAMETERS', r.uri.queryParameters),
      ],
      if (r.error != null) ...<Widget>[
        const SizedBox(height: 12),
        inspectorField(
          'ERROR',
          copyValue: r.error,
          child: SelectableText(
            r.error!,
            style: inspectorMono.copyWith(color: InspectorColors.error),
          ),
        ),
      ],
      const SizedBox(height: 12),
      _headers('REQUEST HEADERS', r.requestHeaders),
      const SizedBox(height: 12),
      _payload('REQUEST PAYLOAD', r.requestBody, truncated: r.requestTruncated),
      const SizedBox(height: 12),
      _headers('RESPONSE HEADERS', r.responseHeaders),
      const SizedBox(height: 12),
      _payload('RESPONSE PAYLOAD', r.responseBody, truncated: r.responseTruncated),
    ],
  );

  Widget _headers(String title, Map<String, String> headers) => inspectorField(
    title,
    copyValue: headers.isEmpty ? null : headers,
    child: headers.isEmpty
        ? inspectorAbsent
        : SelectableText(
            headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            style: inspectorMono.copyWith(color: Colors.white70, height: 1.4),
          ),
  );

  Widget _payload(String title, Object? body, {required bool truncated}) => inspectorField(
    truncated ? '$title (TRUNCATED)' : title,
    copyValue: body,
    child: switch (body) {
      null => inspectorAbsent,
      Map() || List() => StateTreeView(value: body),
      _ => SelectableText(_truncate('$body'), style: inspectorMono),
    },
  );

  /// Long raw bodies (HTML error pages, base64) would make the page janky;
  /// the copy button still copies the full value.
  static String _truncate(String text, [int max = 20000]) =>
      text.length <= max ? text : '${text.substring(0, max)}\n… (${text.length - max} more chars)';
}

/// A colored status code badge: pending, network error, or HTTP status.
class StatusBadge extends StatelessWidget {
  /// Creates a badge for [record].
  const StatusBadge({required this.record, super.key});

  /// The call to show the status of.
  final SnoopCallRecord record;

  @override
  Widget build(BuildContext context) {
    final code = record.statusCode ?? 0;
    final (String text, Color color) = switch (record) {
      SnoopCallRecord(cancelled: true) => ('CXL', Colors.white38),
      SnoopCallRecord(completed: false) => ('···', Colors.white38),
      SnoopCallRecord(errorType: 'superseded') => ('RTY', Colors.white38),
      SnoopCallRecord(statusCode: null) => ('ERR', InspectorColors.error),
      _ when code >= 500 => ('$code', InspectorColors.error),
      _ when code >= 400 => ('$code', InspectorColors.warning),
      _ when code >= 300 => ('$code', InspectorColors.info),
      _ => ('$code', InspectorColors.success),
    };
    return InspectorTag(text, color: color);
  }
}
