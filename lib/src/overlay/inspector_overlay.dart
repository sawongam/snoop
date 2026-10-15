import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:snoop/src/bloc/bloc_inspector_registry.dart';
import 'package:snoop/src/bloc/bloc_inspector_view.dart';
import 'package:snoop/src/dio/dio_inspector_registry.dart';
import 'package:snoop/src/dio/dio_inspector_view.dart';
import 'package:snoop/src/inspector_registry.dart';
import 'package:snoop/src/logs/log_inspector_registry.dart';
import 'package:snoop/src/logs/log_inspector_view.dart';
import 'package:snoop/src/overlay/inspector_toggle.dart';
import 'package:snoop/src/routes/route_inspector_registry.dart';
import 'package:snoop/src/routes/route_inspector_view.dart';
import 'package:snoop/src/widgets/inspector_shared.dart';
import 'package:snoop/src/widgets/live_builder.dart';
import 'package:snoop/src/widgets/snoop_icon.dart';

/// Called when the user drops the bubble, with values that can be passed
/// back as [SnoopOverlay.initialBubbleAlignment] and
/// [SnoopOverlay.bubbleOnLeft] to restore the spot.
typedef SnoopBubbleMoved = void Function(double alignment, bool onLeft);

/// The inspectors the panel can show.
enum SnoopTab {
  /// Recorded Dio calls.
  dio,

  /// Live blocs and cubits.
  bloc,

  /// Recorded log lines.
  logs,

  /// Recorded navigations.
  routes;

  /// Placeholder for this tab's search field.
  String get searchHint => switch (this) {
    SnoopTab.dio => 'URL, method or status',
    SnoopTab.bloc => 'Filter live blocs',
    SnoopTab.logs => 'Message, source or error',
    SnoopTab.routes => 'Route name',
  };

  /// Tab label with its live count.
  String get label => switch (this) {
    SnoopTab.dio => 'Dio ${DioInspectorRegistry.instance.count}',
    SnoopTab.bloc => 'Bloc ${BlocInspectorRegistry.instance.count}',
    SnoopTab.logs => 'Logs ${LogInspectorRegistry.instance.count}',
    SnoopTab.routes => 'Routes ${RouteInspectorRegistry.instance.count}',
  };
}

/// An in-app dev-tools overlay: a draggable edge bubble that opens the
/// inspector as a modal bottom sheet with Bloc, Dio, Logs and Routes tabs.
///
/// Mount it through `MaterialApp.builder`:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => SnoopOverlay(child: child!),
/// )
/// ```
///
/// When [enabled] is false (the default outside debug mode) it returns
/// [child] untouched, so it has no footprint in release builds.
///
/// The bubble and sheet live on the overlay's own [Navigator], above the
/// app's, so they need no navigator key, float over every route and dialog,
/// and use their own dark theme instead of the app's, tinted with the app's
/// primary color (see [accentColor]). While the sheet is open
/// the system back button closes it (or leaves a detail page) instead of
/// popping the app's route.
///
/// The bubble snaps to the nearer side edge when released and shows a red
/// dot when something failed. Long-press it, or use the switch in the panel
/// header, to hide it; [Snoop.bubble] holds that choice.
class SnoopOverlay extends StatefulWidget {
  /// Creates the overlay.
  const SnoopOverlay({
    required this.child,
    this.enabled = kDebugMode,
    this.toggles = const <SnoopToggle>[],
    this.tabs = SnoopTab.values,
    this.initialBubbleAlignment = 0.62,
    this.bubbleOnLeft = false,
    this.accentColor,
    this.onBubbleMoved,
    this.onBubbleVisibilityChanged,
    super.key,
  }) : assert(
         initialBubbleAlignment >= 0 && initialBubbleAlignment <= 1,
         'initialBubbleAlignment must be between 0.0 and 1.0',
       );

  /// The app.
  final Widget child;

  /// Whether the overlay is shown. Defaults to [kDebugMode].
  final bool enabled;

  /// Your own debug controls, shown in a bar at the top of the panel: a
  /// button ([SnoopToggle.action]), an on/off switch
  /// ([SnoopToggle.switcher]) or a choice of options
  /// ([SnoopSegmentedToggle]). Handy for flipping theme, locale, feature
  /// flags or a fake login while testing. Empty (the default) hides the bar.
  ///
  /// See [SnoopToggle] for how values stay in sync.
  final List<SnoopToggle> toggles;

  /// Which inspectors to show, in order. Empty means all.
  final List<SnoopTab> tabs;

  /// Where the bubble starts vertically, from `0.0` (top) to `1.0` (bottom)
  /// of the area it can move in: the screen minus the status bar, the
  /// bottom system bar or keyboard, and an 8px gutter at each end.
  ///
  /// Defaults to `0.62`, a little below the middle, clear of app bars and
  /// bottom navigation. Once the bubble has been dragged it stays where it
  /// was dropped.
  final double initialBubbleAlignment;

  /// Whether the bubble starts on the left edge instead of the right.
  final bool bubbleOnLeft;

  /// Color of the bubble and the panel's highlights. Defaults to the app's
  /// `colorScheme.primary`. Inside the dark panel it is lightened as needed
  /// to stay readable.
  final Color? accentColor;

  /// Called when the user drops the bubble after dragging it, once it has
  /// snapped to an edge. `alignment` (0.0 to 1.0) and `onLeft` match
  /// [initialBubbleAlignment] and [bubbleOnLeft], so saving them and passing
  /// them back on the next launch puts the bubble where it was left:
  ///
  /// ```dart
  /// SnoopOverlay(
  ///   initialBubbleAlignment: prefs.getDouble('snoop.y') ?? 0.62,
  ///   bubbleOnLeft: prefs.getBool('snoop.left') ?? false,
  ///   onBubbleMoved: (alignment, onLeft) {
  ///     prefs.setDouble('snoop.y', alignment);
  ///     prefs.setBool('snoop.left', onLeft);
  ///   },
  ///   child: child!,
  /// )
  /// ```
  final SnoopBubbleMoved? onBubbleMoved;

  /// Called with the new value whenever the bubble is hidden or shown: by a
  /// long-press on it, its undo toast, the switch in the panel header, or
  /// code setting [Snoop.bubble].
  ///
  /// To restore the choice on the next launch, save it here and seed
  /// [Snoop.bubble] before `runApp`.
  final ValueChanged<bool>? onBubbleVisibilityChanged;

  /// Opens the panel of the nearest [SnoopOverlay], if any, optionally
  /// on [tab].
  static void open(BuildContext context, {SnoopTab? tab}) =>
      context.findAncestorStateOfType<_SnoopOverlayState>()?._open(tab: tab);

  /// Closes the panel of the nearest [SnoopOverlay], if any.
  static void close(BuildContext context) =>
      context.findAncestorStateOfType<_SnoopOverlayState>()?._close();

  @override
  State<SnoopOverlay> createState() => _SnoopOverlayState();
}

/// Panel state that outlives the sheet, so closing and reopening it keeps the
/// selected tab and each tab's search.
class _Session extends ChangeNotifier {
  SnoopTab? tab;
  final Map<SnoopTab, TextEditingController> queries = <SnoopTab, TextEditingController>{
    for (final tab in SnoopTab.values) tab: TextEditingController(),
  };
  final Set<SnoopTab> searchOpen = <SnoopTab>{};

  void select(SnoopTab value) {
    tab = value;
    notifyListeners();
  }

  void toggleSearch(SnoopTab tab) {
    if (!searchOpen.remove(tab)) searchOpen.add(tab);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final controller in queries.values) {
      controller.dispose();
    }
    super.dispose();
  }
}

class _SnoopOverlayState extends State<SnoopOverlay> {
  final GlobalKey _appKey = GlobalKey();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _sheetNavigatorKey = GlobalKey<NavigatorState>();
  final _Session _session = _Session();

  /// True while the sheet is up; hides the bubble so it never sits on the
  /// inspector it opened.
  final ValueNotifier<bool> _isOpen = ValueNotifier<bool>(false);

  Route<void>? _sheetRoute;

  /// Placed on the app's top route while the sheet is open, so the system
  /// back button reaches us before it pops the app.
  LocalHistoryEntry? _backEntry;
  ModalRoute<Object?>? _backRoute;

  List<SnoopTab> get _tabs => widget.tabs.isEmpty ? SnoopTab.values : widget.tabs;

  @override
  void initState() {
    super.initState();
    Snoop.bubble.addListener(_bubbleVisibilityChanged);
  }

  @override
  void didUpdateWidget(SnoopOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _close();
  }

  @override
  void dispose() {
    Snoop.bubble.removeListener(_bubbleVisibilityChanged);
    _releaseBack();
    _session.dispose();
    _isOpen.dispose();
    super.dispose();
  }

  Future<void> _open({SnoopTab? tab}) async {
    if (tab != null) _session.select(tab);
    final navigator = _navigatorKey.currentState;
    if (navigator == null || _sheetRoute != null) return;

    final route = ModalBottomSheetRoute<void>(
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: InspectorColors.panel,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      barrierLabel: 'Close Snoop',
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        // Detail pages push on this navigator, so they stay inside the sheet.
        child: Navigator(
          key: _sheetNavigatorKey,
          onGenerateInitialRoutes: (_, _) => <Route<void>>[
            MaterialPageRoute<void>(
              builder: (_) => _InspectorPanel(
                session: _session,
                tabs: _tabs,
                toggles: widget.toggles,
                onClose: _close,
              ),
            ),
          ],
        ),
      ),
    );
    _sheetRoute = route;
    _isOpen.value = true;
    _guardBack();
    try {
      await navigator.push(route);
    } finally {
      _sheetRoute = null;
      _releaseBack();
      if (mounted) _isOpen.value = false;
    }
  }

  void _close() => _navigatorKey.currentState?.popUntil((route) => route.isFirst);

  // Read `widget` at call time: the bubble's overlay entry is built once and
  // would otherwise keep the first callbacks.
  void _bubbleVisibilityChanged() => widget.onBubbleVisibilityChanged?.call(Snoop.bubble.value);

  void _bubbleMoved(double alignment, bool onLeft) => widget.onBubbleMoved?.call(alignment, onLeft);

  // --- System back -----------------------------------------------------------

  void _guardBack() {
    if (_backEntry != null) return;
    final route = _appTopRoute();
    if (route == null) return;
    final entry = LocalHistoryEntry(onRemove: _onBackEntryRemoved, impliesAppBarDismissal: false);
    _backEntry = entry;
    _backRoute = route;
    route.addLocalHistoryEntry(entry);
  }

  void _releaseBack() {
    final entry = _backEntry;
    final route = _backRoute;
    _backEntry = null;
    _backRoute = null;
    // The app may have navigated away from that route meanwhile.
    if (entry != null && route != null && route.isActive) entry.remove();
  }

  /// The app's navigator popped our entry: the user pressed back. Step back
  /// inside the inspector instead.
  void _onBackEntryRemoved() {
    if (_backEntry == null) return; // We removed it ourselves.
    _backEntry = null;
    _backRoute = null;
    final sheetRoute = _sheetRoute;
    if (sheetRoute == null) return;
    final sheetNavigator = _sheetNavigatorKey.currentState;
    if (sheetRoute.isCurrent && sheetNavigator != null && sheetNavigator.canPop()) {
      sheetNavigator.pop();
    } else {
      _navigatorKey.currentState?.pop();
    }
    // If the sheet is still open (we only left a detail page or a value
    // sheet), keep guarding. A closed sheet has cleared `_sheetRoute` by then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _sheetRoute == sheetRoute) _guardBack();
    });
  }

  /// The top route of the app's navigator: the first [NavigatorState] below
  /// the app's subtree.
  ModalRoute<Object?>? _appTopRoute() {
    final root = _appKey.currentContext;
    if (root == null) return null;
    NavigatorState? navigator;
    void visit(Element element) {
      if (navigator != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        navigator = element.state as NavigatorState;
        return;
      }
      element.visitChildren(visit);
    }

    (root as Element).visitChildren(visit);
    Route<Object?>? top;
    navigator?.popUntil((route) {
      top = route;
      return true;
    });
    return top is ModalRoute<Object?> ? top as ModalRoute<Object?> : null;
  }

  @override
  Widget build(BuildContext context) {
    final app = KeyedSubtree(key: _appKey, child: widget.child);
    if (!widget.enabled) return app;

    return Stack(
      // Explicit, so the app below keeps its own ambient directionality.
      textDirection: TextDirection.ltr,
      children: <Widget>[
        app,
        // Empty regions of the chrome have no hit target, so touches pass
        // through to the app when only the bubble is shown.
        Positioned.fill(
          child: _InspectorTheme(
            accent: widget.accentColor ?? Theme.of(context).colorScheme.primary,
            // Our navigator's "can pop" must not overwrite the app's in
            // `SystemNavigator.setFrameworkHandlesBack`.
            child: NotificationListener<NavigationNotification>(
              onNotification: (_) => true,
              // The app's HeroController belongs to the app's navigator.
              child: HeroControllerScope.none(
                child: Navigator(
                  key: _navigatorKey,
                  onGenerateInitialRoutes: (_, _) => <Route<void>>[
                    _BubbleRoute(
                      builder: (_) => _BubbleLayer(
                        isOpen: _isOpen,
                        alignment: widget.initialBubbleAlignment,
                        startOnLeft: widget.bubbleOnLeft,
                        onTap: _open,
                        onMoved: _bubbleMoved,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The base of the overlay's navigator: a non-modal route (no barrier, so
/// touches reach the app) holding the bubble.
class _BubbleRoute extends OverlayRoute<void> {
  _BubbleRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  Iterable<OverlayEntry> createOverlayEntries() => <OverlayEntry>[OverlayEntry(builder: builder)];
}

/// Supplies what the chrome needs regardless of where it is mounted: LTR
/// directionality, the inspector's dark theme tinted with [accent], and media query /
/// localizations fallbacks when used outside a `MaterialApp`.
class _InspectorTheme extends StatelessWidget {
  const _InspectorTheme({required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget result = Theme(
      data: inspectorTheme(accent),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );
    if (Localizations.of<MaterialLocalizations>(context, MaterialLocalizations) == null) {
      result = Localizations(
        locale: const Locale('en'),
        delegates: const <LocalizationsDelegate<Object?>>[
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: result,
      );
    }
    if (MediaQuery.maybeOf(context) == null) {
      result = MediaQuery.fromView(view: View.of(context), child: result);
    }
    return result;
  }
}

// --- Bubble ------------------------------------------------------------------

class _BubbleLayer extends StatefulWidget {
  const _BubbleLayer({
    required this.isOpen,
    required this.alignment,
    required this.startOnLeft,
    required this.onTap,
    required this.onMoved,
  });

  final ValueListenable<bool> isOpen;
  final double alignment;
  final bool startOnLeft;
  final VoidCallback onTap;
  final SnoopBubbleMoved onMoved;

  @override
  State<_BubbleLayer> createState() => _BubbleLayerState();
}

class _BubbleLayerState extends State<_BubbleLayer> {
  static const double _width = 40;
  static const double _height = 48;
  static const double _gutter = 8;

  late final Listenable _changes = Listenable.merge(<Listenable>[Snoop.bubble, widget.isOpen]);

  /// Resting top-left, or `null` for the default spot.
  Offset? _position;

  /// Non-null while a finger drags the bubble.
  Offset? _drag;

  /// Shown for a few seconds after a long-press hides the bubble.
  bool _showUndo = false;
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  void _hide() {
    Snoop.bubble.value = false;
    _undoTimer?.cancel();
    setState(() => _showUndo = true);
    _undoTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showUndo = false);
    });
  }

  void _undo() {
    _undoTimer?.cancel();
    Snoop.bubble.value = true;
    setState(() => _showUndo = false);
  }

  /// The rectangle the bubble's top-left may occupy: the view minus system
  /// insets and keyboard, flush with the side edges.
  Rect _bounds(Size area) {
    final padding = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final top = padding.top + _gutter;
    final right = (area.width - padding.right - _width).clamp(padding.left, double.infinity);
    final bottom =
        (area.height - (keyboard > padding.bottom ? keyboard : padding.bottom) - _gutter - _height)
            .clamp(top, double.infinity);
    return Rect.fromLTRB(padding.left, top, right, bottom);
  }

  Offset _clamp(Offset o, Rect b) =>
      Offset(o.dx.clamp(b.left, b.right), o.dy.clamp(b.top, b.bottom));

  /// Parks [o] on whichever side edge it is nearer.
  Offset _snap(Offset o, Rect b) {
    final c = _clamp(o, b);
    return Offset(c.dx - b.left <= b.right - c.dx ? b.left : b.right, c.dy);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _changes,
    builder: (context, _) {
      final visible = Snoop.bubble.value && !widget.isOpen.value;
      return Stack(
        children: <Widget>[
          if (visible) Positioned.fill(child: LayoutBuilder(builder: _buildBubble)),
          if (_showUndo && !Snoop.bubble.value) _undoToast(),
        ],
      );
    },
  );

  Widget _buildBubble(BuildContext context, BoxConstraints constraints) {
    final bounds = _bounds(constraints.biggest);
    final resting = _clamp(
      _position ??
          Offset(
            widget.startOnLeft ? bounds.left : bounds.right,
            bounds.top + bounds.height * widget.alignment,
          ),
      bounds,
    );
    final offset = _drag ?? resting;
    final onLeft = offset.dx - bounds.left <= bounds.right - offset.dx;

    return Stack(
      children: <Widget>[
        AnimatedPositioned(
          duration: _drag != null ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: offset.dx,
          top: offset.dy,
          child: GestureDetector(
            key: const ValueKey<String>('snoop.bubble'),
            onTap: widget.onTap,
            onLongPress: _hide,
            onPanStart: (_) => setState(() => _drag = resting),
            onPanUpdate: (d) =>
                setState(() => _drag = _clamp((_drag ?? resting) + d.delta, bounds)),
            onPanEnd: (_) {
              final position = _snap(_drag ?? resting, bounds);
              setState(() {
                _position = position;
                _drag = null;
              });
              widget.onMoved(
                bounds.height > 0 ? (position.dy - bounds.top) / bounds.height : 0,
                position.dx == bounds.left,
              );
            },
            onPanCancel: () => setState(() => _drag = null),
            child: _Bubble(width: _width, height: _height, onLeft: onLeft, dragging: _drag != null),
          ),
        ),
      ],
    );
  }

  Widget _undoToast() => Positioned(
    left: 16,
    right: 16,
    bottom: MediaQuery.paddingOf(context).bottom + 24,
    child: Center(
      child: Material(
        color: InspectorColors.card,
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Snoop bubble hidden',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _undo, child: const Text('UNDO')),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The bubble: an edge-docked tab, rounded only on its inward side, with an
/// error dot when anything failed.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.width,
    required this.height,
    required this.onLeft,
    required this.dragging,
  });

  final double width;
  final double height;
  final bool onLeft;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(14);
    return Semantics(
      button: true,
      label: 'Open Snoop',
      hint: 'Long-press to hide',
      child: AnimatedScale(
        scale: dragging ? 1.06 : 1,
        duration: const Duration(milliseconds: 120),
        child: Material(
          color: InspectorColors.bubbleOf(context),
          elevation: 6,
          borderRadius: onLeft
              ? const BorderRadius.only(topRight: r, bottomRight: r)
              : const BorderRadius.only(topLeft: r, bottomLeft: r),
          child: SizedBox(
            width: width,
            height: height,
            child: ListenableBuilder(
              listenable: Snoop.listenable,
              builder: (context, _) => Stack(
                children: <Widget>[
                  Center(
                    child: SnoopIcon.bug(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  if (Snoop.errorCount > 0)
                    Positioned(
                      top: 7,
                      right: onLeft ? 7 : null,
                      left: onLeft ? null : 7,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: InspectorColors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Panel -------------------------------------------------------------------

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({
    required this.session,
    required this.tabs,
    required this.toggles,
    required this.onClose,
  });

  final _Session session;
  final List<SnoopTab> tabs;
  final List<SnoopToggle> toggles;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: InspectorColors.panel,
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final tab = tabs.contains(session.tab) ? session.tab! : tabs.first;
          final query = session.queries[tab]!;
          final showsSearch = session.searchOpen.contains(tab) || query.text.isNotEmpty;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(
                showsSearch: showsSearch,
                onSearch: () => session.toggleSearch(tab),
                onClose: onClose,
              ),
              if (toggles.isNotEmpty) ...<Widget>[
                const Divider(height: 1, color: InspectorColors.divider),
                InspectorToggleBar(toggles: toggles),
              ],
              if (tabs.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: LiveBuilder(
                    listenable: Snoop.listenable,
                    builder: (context) => InspectorSegmented<SnoopTab>(
                      expand: true,
                      value: tab,
                      segments: <(SnoopTab, String)>[for (final t in tabs) (t, t.label)],
                      onChanged: session.select,
                    ),
                  ),
                ),
              if (showsSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: InspectorSearchField(
                    // Keyed per tab so switching tabs moves focus to a fresh field.
                    key: ValueKey<SnoopTab>(tab),
                    controller: query,
                    hint: tab.searchHint,
                    autofocus: query.text.isEmpty,
                  ),
                ),
              const SizedBox(height: 6),
              const Divider(height: 1, color: InspectorColors.divider),
              Expanded(
                // Every tab stays mounted so switching keeps its scroll and
                // state; only the visible one updates live.
                child: IndexedStack(
                  index: tabs.indexOf(tab),
                  children: <Widget>[
                    for (final t in tabs)
                      TickerMode(
                        enabled: t == tab,
                        child: switch (t) {
                          SnoopTab.bloc => BlocInspectorView(query: session.queries[t]!),
                          SnoopTab.dio => DioInspectorView(query: session.queries[t]!),
                          SnoopTab.logs => LogInspectorView(query: session.queries[t]!),
                          SnoopTab.routes => RouteInspectorView(query: session.queries[t]!),
                        },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Title, the bubble switch, search, clear all, close.
class _Header extends StatelessWidget {
  const _Header({required this.showsSearch, required this.onSearch, required this.onClose});

  final bool showsSearch;
  final VoidCallback onSearch;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 4, 4),
    child: Row(
      children: <Widget>[
        SnoopIcon.bug(color: InspectorColors.accentOf(context), size: 20),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Snoop Inspector',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        const _BubbleSwitch(),
        inspectorGlyph(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          active: showsSearch,
          onTap: onSearch,
        ),
        LiveBuilder(
          listenable: Snoop.listenable,
          builder: (context) => inspectorGlyph(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear all records',
            onTap: Snoop.hasRecords ? Snoop.clearAll : null,
          ),
        ),
        inspectorGlyph(icon: const Icon(Icons.close), tooltip: 'Close', onTap: onClose),
      ],
    ),
  );
}

/// Turns the floating bubble on or off.
class _BubbleSwitch extends StatelessWidget {
  const _BubbleSwitch();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: Snoop.bubble,
    builder: (context, isOn, _) => Tooltip(
      message: isOn ? 'Hide floating bubble' : 'Show floating bubble',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.bubble_chart_outlined,
            size: 17,
            color: isOn ? InspectorColors.accentOf(context) : Colors.white38,
          ),
          SizedBox(
            height: 28,
            child: FittedBox(
              child: Switch(
                key: const ValueKey<String>('snoop.bubble_switch'),
                value: isOn,
                activeThumbColor: Colors.white,
                activeTrackColor: InspectorColors.accentOf(context),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (value) => Snoop.bubble.value = value,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
