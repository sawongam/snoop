import 'package:flutter/material.dart';
import 'package:snoop/src/routes/route_inspector_registry.dart';
import 'package:snoop/src/widgets/inspector_shared.dart';
import 'package:snoop/src/widgets/live_builder.dart';
import 'package:snoop/src/widgets/value_sheet.dart';

/// The Routes tab: pushes, pops and replaces, newest first. A route that was
/// given arguments opens them in a value sheet.
///
/// It answers what a redirect bug always raises: did the app go somewhere it
/// immediately left, and what arrived as the route's arguments?
class RouteInspectorView extends StatelessWidget {
  /// Creates the view.
  const RouteInspectorView({required this.query, super.key});

  /// Search query owned by the panel header.
  final TextEditingController query;

  RouteInspectorRegistry get _registry => RouteInspectorRegistry.instance;

  @override
  Widget build(BuildContext context) => LiveBuilder(
    listenable: Listenable.merge(<Listenable>[_registry, query]),
    builder: (context) {
      final records = _registry.records;
      if (records.isEmpty) {
        return inspectorEmpty(
          'No navigation recorded',
          message: 'Add SnoopRouteObserver() to your navigatorObservers to record routes.',
          icon: Icons.alt_route_rounded,
        );
      }
      final needle = query.text.trim().toLowerCase();
      final visible = records.where((r) => r.matches(needle)).toList(growable: false);
      if (visible.isEmpty) return inspectorNoMatches('No routes match "$needle"');
      return ListView.builder(
        itemCount: visible.length,
        itemBuilder: (context, i) => _RouteTile(record: visible[i]),
      );
    },
  );
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({required this.record});

  final SnoopRouteRecord record;

  @override
  Widget build(BuildContext context) {
    final arguments = record.arguments;
    return InspectorRow(
      onTap: arguments == null
          ? null
          : () => showValueSheet(
              context: context,
              title: 'arguments · ${record.name}',
              value: arguments,
            ),
      leading: InspectorTag(
        record.action.label,
        color: switch (record.action) {
          SnoopRouteAction.push => InspectorColors.success,
          SnoopRouteAction.pop => Colors.white54,
          SnoopRouteAction.replace => InspectorColors.info,
          SnoopRouteAction.remove => InspectorColors.warning,
        },
      ),
      title: Text(record.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: inspectorMono),
      subtitle: inspectorMeta(<String>[
        inspectorTime(record.timestamp),
        'depth ${record.depth}',
        if (record.previousName != null) 'under ${record.previousName}',
        if (arguments != null) 'has arguments',
      ]),
    );
  }
}
