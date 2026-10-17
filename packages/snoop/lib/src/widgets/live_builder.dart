import 'package:flutter/widgets.dart';

/// Like [ListenableBuilder], but ignores notifications while the subtree is
/// hidden (its [TickerMode] is disabled) and rebuilds once when it is shown
/// again.
///
/// The inspector panel stays mounted while closed so it keeps its navigation
/// and scroll state. Without this, every bloc emit and every request would
/// still rebuild the hidden panel.
class LiveBuilder extends StatefulWidget {
  /// Creates a live builder.
  const LiveBuilder({required this.listenable, required this.builder, super.key});

  /// What to listen to.
  final Listenable listenable;

  /// Builds the subtree.
  final WidgetBuilder builder;

  @override
  State<LiveBuilder> createState() => _LiveBuilderState();
}

class _LiveBuilderState extends State<LiveBuilder> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onChange);
  }

  @override
  void didUpdateWidget(LiveBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_onChange);
      widget.listenable.addListener(_onChange);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    // Becoming visible is a dependency change, which rebuilds us anyway and
    // picks up everything skipped while hidden.
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    if (_visible) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
