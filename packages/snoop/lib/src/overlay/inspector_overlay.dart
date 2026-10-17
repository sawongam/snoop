import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:snoop/src/export.dart';
import 'package:snoop/src/inspector_registry.dart';
import 'package:snoop/src/overlay/inspector_toggle.dart';
import 'package:snoop/src/overlay/snoop_tab.dart';
import 'package:snoop/src/version.dart';
import 'package:snoop/src/widgets/inspector_shared.dart';
import 'package:snoop/src/widgets/live_builder.dart';
import 'package:snoop/src/widgets/snoop_icon.dart';

/// Called when the user drops the bubble, with values that can be passed
/// back as [SnoopOverlay.initialBubbleAlignment] and
/// [SnoopOverlay.bubbleOnLeft] to restore the spot.
typedef SnoopBubbleMoved = void Function(double alignment, bool onLeft);

/// An in-app dev-tools overlay: a draggable edge bubble that opens the
/// inspector as a modal bottom sheet with Network, State, Logs and Routes
/// tabs.
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
    this.title = 'Snoop Inspector',
    this.toggles = const <SnoopToggle>[],
    this.tabs,
    this.initialBubbleAlignment = 0.62,
    this.bubbleOnLeft = false,
    this.accentColor,
    this.onBubbleMoved,
    this.onBubbleVisibilityChanged,
    this.onExport,
    super.key,
  }) : assert(
         initialBubbleAlignment >= 0 && initialBubbleAlignment <= 1,
         'initialBubbleAlignment must be between 0.0 and 1.0',
       );

  /// The app.
  final Widget child;

  /// Whether the overlay is shown. Defaults to [kDebugMode].
  final bool enabled;

  /// Title shown at the top of the panel. Defaults to `Snoop Inspector`.
  final String title;

  /// Your own debug controls, shown in a bar at the top of the panel: a
  /// button ([SnoopToggle.action]), an on/off switch
  /// ([SnoopToggle.switcher]) or a choice of options
  /// ([SnoopSegmentedToggle]). Handy for flipping theme, locale, feature
  /// flags or a fake login while testing. Empty (the default) hides the bar.
  ///
  /// See [SnoopToggle] for how values stay in sync.
  final List<SnoopToggle> toggles;

  /// Which tabs to show, in order. `null` or empty means
  /// [SnoopTab.defaults]. Add your own [SnoopTab]s for app-specific panels.
  ///
  /// A tab whose [SnoopTab.isAvailable] returns false is hidden: the Network
  /// and State tabs stay hidden until an adapter of their kind is installed.
  final List<SnoopTab>? tabs;

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

  /// Receives files from the Export action in the panel's action bar: the
  /// recorded calls as HAR, or the whole session as JSON.
  ///
  /// Snoop has no share or file dependency, so by default an export is
  /// copied to the clipboard and echoed to the console. Hand it to the share
  /// sheet instead, e.g. with `share_plus`:
  ///
  /// ```dart
  /// SnoopOverlay(
  ///   onExport: (export) => SharePlus.instance.share(
  ///     ShareParams(
  ///       files: [XFile.fromData(utf8.encode(export.contents), mimeType: export.mimeType)],
  ///       fileNameOverrides: [export.fileName],
  ///     ),
  ///   ),
  ///   child: child!,
  /// )
  /// ```
  final SnoopExportHandler? onExport;

  /// Opens the panel of the nearest [SnoopOverlay], if any, optionally on
  /// the tab with id [tab] (`'network'`, `'state'`, `'logs'`, `'routes'` or a
  /// custom tab's id).
  static void open(BuildContext context, {String? tab}) =>
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
  String? tab;
  final Map<String, TextEditingController> _queries = <String, TextEditingController>{};
  final Set<String> searchOpen = <String>{};

  TextEditingController query(String tab) => _queries.putIfAbsent(tab, TextEditingController.new);

  void select(String value) {
    tab = value;
    notifyListeners();
  }

  void toggleSearch(String tab) {
    if (!searchOpen.remove(tab)) searchOpen.add(tab);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final controller in _queries.values) {
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

  List<SnoopTab> get _tabs {
    final tabs = widget.tabs;
    return tabs == null || tabs.isEmpty ? SnoopTab.defaults : tabs;
  }

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
    if (_sheetRoute != null) snoopPanelOpen.value = false;
    _releaseBack();
    _session.dispose();
    _isOpen.dispose();
    super.dispose();
  }

  Future<void> _open({String? tab}) async {
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
                title: widget.title,
                toggles: widget.toggles,
                onClose: _close,
                onExport: _export,
              ),
            ),
          ],
        ),
      ),
    );
    _sheetRoute = route;
    _isOpen.value = true;
    snoopPanelOpen.value = true;
    _guardBack();
    try {
      await navigator.push(route);
    } finally {
      _sheetRoute = null;
      _releaseBack();
      snoopPanelOpen.value = false;
      if (mounted) _isOpen.value = false;
    }
  }

  void _close() => _navigatorKey.currentState?.popUntil((route) => route.isFirst);

  // Read `widget` at call time, like the bubble callbacks below.
  Future<void> _export(SnoopExport export) async {
    final handler = widget.onExport;
    if (handler == null) return snoopCopy(export.contents);
    await handler(export);
  }

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
                        tabs: () => _tabs,
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
    required this.tabs,
    required this.alignment,
    required this.startOnLeft,
    required this.onTap,
    required this.onMoved,
  });

  final ValueListenable<bool> isOpen;
  final List<SnoopTab> Function() tabs;
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
            child: _Bubble(
              width: _width,
              height: _height,
              onLeft: onLeft,
              dragging: _drag != null,
              tabs: widget.tabs(),
            ),
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
    required this.tabs,
  });

  final double width;
  final double height;
  final bool onLeft;
  final bool dragging;
  final List<SnoopTab> tabs;

  int get _errors {
    var errors = 0;
    for (final tab in tabs) {
      errors += tab.errorCount?.call() ?? 0;
    }
    return errors;
  }

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
              listenable: Listenable.merge(<Listenable>[
                Snoop.listenable,
                for (final t in tabs) t.listenable,
              ]),
              builder: (context, _) => Stack(
                children: <Widget>[
                  Center(
                    child: SnoopIcon.bug(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  if (_errors > 0)
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
    required this.title,
    required this.toggles,
    required this.onClose,
    required this.onExport,
  });

  final _Session session;
  final List<SnoopTab> tabs;
  final String title;
  final List<SnoopToggle> toggles;
  final VoidCallback onClose;
  final SnoopExportHandler onExport;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: InspectorColors.panel,
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) => LiveBuilder(
          listenable: Listenable.merge(<Listenable>[
            Snoop.listenable,
            for (final t in tabs) t.listenable,
          ]),
          builder: (context) => _build(context, <SnoopTab>[
            for (final t in tabs)
              if (t.available) t,
          ]),
        ),
      ),
    ),
  );

  Widget _build(BuildContext context, List<SnoopTab> visible) {
    // Logs and Routes are always available, so this only empties when every
    // tab passed in is unavailable; fall back to showing them all.
    final tabs = visible.isEmpty ? this.tabs : visible;
    // A selected tab that disappeared falls back to the first visible one.
    final tab = tabs.firstWhere((t) => t.id == session.tab, orElse: () => tabs.first);
    final query = session.query(tab.id);
    final showsSearch = session.searchOpen.contains(tab.id) || query.text.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(
          title: title,
          showsSearch: showsSearch,
          onSearch: () => session.toggleSearch(tab.id),
          onExport: onExport,
          onClose: onClose,
        ),
        const Divider(height: 1, color: InspectorColors.divider),
        if (toggles.isNotEmpty) InspectorToggleBar(toggles: toggles),
        if (tabs.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: InspectorSegmented<String>(
              expand: true,
              value: tab.id,
              segments: <(String, String)>[for (final t in tabs) (t.id, t.title)],
              onChanged: session.select,
            ),
          ),
        if (showsSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: InspectorSearchField(
              // Keyed per tab so switching tabs moves focus to a fresh field.
              key: ValueKey<String>(tab.id),
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
                  key: ValueKey<String>(t.id),
                  enabled: t == tab,
                  child: Builder(builder: (context) => t.builder(context, session.query(t.id))),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bug, title, the bubble switch, search, clear all, more, close.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.showsSearch,
    required this.onSearch,
    required this.onExport,
    required this.onClose,
  });

  final String title;
  final bool showsSearch;
  final VoidCallback onSearch;
  final SnoopExportHandler onExport;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 4, 4),
    child: Row(
      children: <Widget>[
        // The title takes all the room the actions leave, truncating only
        // when there is truly none.
        Expanded(
          child: Row(
            children: <Widget>[
              // Lit while the bubble is showing, like the switch beside the title.
              ValueListenableBuilder<bool>(
                valueListenable: Snoop.bubble,
                builder: (context, isOn, _) => SnoopIcon.bug(
                  size: 17,
                  color: isOn ? InspectorColors.accentOf(context) : Colors.white38,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const _BubbleSwitch(),
            ],
          ),
        ),
        inspectorGlyph(
          icon: const SnoopIcon.search(),
          tooltip: 'Search',
          active: showsSearch,
          onTap: onSearch,
        ),
        LiveBuilder(
          listenable: Snoop.listenable,
          builder: (context) => inspectorGlyph(
            icon: const SnoopIcon.trash(),
            tooltip: 'Clear all records',
            onTap: Snoop.hasRecords ? Snoop.clearAll : null,
          ),
        ),
        _MoreMenu(onExport: onExport),
        inspectorGlyph(icon: const Icon(Icons.close), tooltip: 'Close', onTap: onClose),
      ],
    ),
  );
}

enum _ExportKind { har, session }

/// The header's overflow menu: the calls as HAR or everything as JSON,
/// handed to [SnoopOverlay.onExport].
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.onExport});

  final SnoopExportHandler onExport;

  @override
  Widget build(BuildContext context) => LiveBuilder(
    listenable: Snoop.listenable,
    builder: (context) {
      final enabled = Snoop.hasRecords || Snoop.state.count > 0;
      return PopupMenuButton<_ExportKind>(
        key: const ValueKey<String>('snoop.more'),
        tooltip: 'More',
        enabled: enabled,
        color: InspectorColors.card,
        iconSize: 19,
        iconColor: Colors.white70,
        style: IconButton.styleFrom(
          visualDensity: VisualDensity.compact,
          disabledForegroundColor: Colors.white24,
        ),
        icon: const Icon(Icons.more_vert),
        onSelected: (kind) => onExport(switch (kind) {
          _ExportKind.har => harExport(),
          _ExportKind.session => sessionExport(),
        }),
        itemBuilder: (context) => <PopupMenuEntry<_ExportKind>>[
          _item(
            _ExportKind.har,
            'Export network calls (HAR)',
            'Opens in Chrome DevTools, Charles, Proxyman',
            enabled: !Snoop.network.isEmpty,
          ),
          _item(_ExportKind.session, 'Export full session (JSON)', 'Calls, state, logs and routes'),
          const PopupMenuItem<_ExportKind>(
            enabled: false,
            height: 28,
            child: Text(
              'snoop $snoopVersion',
              style: TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ),
        ],
      );
    },
  );

  static PopupMenuItem<_ExportKind> _item(
    _ExportKind kind,
    String title,
    String subtitle, {
    bool enabled = true,
  }) => PopupMenuItem<_ExportKind>(
    value: kind,
    enabled: enabled,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(title, style: TextStyle(color: enabled ? Colors.white : Colors.white38, fontSize: 13)),
        Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
      child: SizedBox(
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
    ),
  );
}
