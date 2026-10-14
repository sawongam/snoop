import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The inspector's dark palette. Only the accent follows the host app (see
/// [accentOf]); everything else looks the same in every app.
abstract final class InspectorColors {
  /// Dimmed backdrop behind the panel.
  static const Color backdrop = Color(0xCC000000);

  /// Panel background.
  static const Color panel = Color(0xFF1E1E24);

  /// Card and box background.
  static const Color card = Color(0xFF2A2A33);

  /// Recessed background (source locations).
  static const Color sunken = Color(0xFF14141A);

  /// Accent: labels, selection, switches. The host app's primary color (or
  /// `SnoopOverlay.accentColor`), lightened to read on [panel].
  static Color accentOf(BuildContext context) => Theme.of(context).colorScheme.primary;

  /// Floating bubble fill: the accent as given, not lightened.
  static Color bubbleOf(BuildContext context) => Theme.of(context).colorScheme.primaryContainer;

  /// Text and icons on [bubbleOf] and on accent fills.
  static Color onAccentOf(BuildContext context) => Theme.of(context).colorScheme.onPrimary;

  /// 2xx and healthy blocs.
  static const Color success = Color(0xFF22C55E);

  /// 4xx and slow calls.
  static const Color warning = Color(0xFFF59E0B);

  /// 5xx, network errors and bloc errors.
  static const Color error = Color(0xFFEF4444);

  /// 3xx.
  static const Color info = Color(0xFF60A5FA);

  /// Bloc events.
  static const Color event = Color(0xFFFBBF24);

  /// Source location icon.
  static const Color link = Color(0xFF7AA2F7);

  /// Source location text.
  static const Color linkText = Color(0xFF9DB4D0);

  /// Dividers.
  static const Color divider = Colors.white12;

  /// Text color for an HTTP method, using Swagger UI's palette: GET blue,
  /// POST green, PUT orange, DELETE red, PATCH teal, HEAD purple, OPTIONS
  /// navy. Colors too dark to read on [panel] (HEAD, OPTIONS) are lightened.
  static Color method(String method) => switch (method.toUpperCase()) {
    'GET' => _get,
    'POST' => _post,
    'PUT' => _put,
    'DELETE' => _delete,
    'PATCH' => _patch,
    'HEAD' => _head,
    'OPTIONS' => _options,
    _ => Colors.white70,
  };

  static final Color _get = _readableOnPanel(const Color(0xFF61AFFE));
  static final Color _post = _readableOnPanel(const Color(0xFF49CC90));
  static final Color _put = _readableOnPanel(const Color(0xFFFCA130));
  static final Color _delete = _readableOnPanel(const Color(0xFFF93E3E));
  static final Color _patch = _readableOnPanel(const Color(0xFF50E3C2));
  static final Color _head = _readableOnPanel(const Color(0xFF9012FE));
  static final Color _options = _readableOnPanel(const Color(0xFF0D5AA7));
}

/// The inspector's own dark Material theme, tinted with [accent]. Apart from
/// the accent the inspector never reads the host app's theme, so it looks the
/// same in every app.
ThemeData inspectorTheme(Color accent) {
  final readable = _readableOnPanel(accent);
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: readable,
      onPrimary: _onColor(readable),
      primaryContainer: accent,
      onPrimaryContainer: _onColor(accent),
      surface: InspectorColors.panel,
    ),
    scaffoldBackgroundColor: InspectorColors.panel,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: readable,
      selectionColor: readable.withValues(alpha: 0.4),
      selectionHandleColor: readable,
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
  );
}

/// [color], blended toward white until it has 4.5:1 contrast (WCAG AA) on
/// the panel, so a dark brand color still works as text.
Color _readableOnPanel(Color color) {
  final minLuminance = 4.5 * (InspectorColors.panel.computeLuminance() + 0.05) - 0.05;
  for (var i = 0; i <= 10; i++) {
    final blended = Color.lerp(color, Colors.white, i / 10)!;
    if (blended.computeLuminance() >= minLuminance) return blended;
  }
  return Colors.white;
}

Color _onColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? Colors.white
    : Colors.black;

/// Monospace text style used for payloads.
const TextStyle inspectorMono = TextStyle(
  color: Colors.white,
  fontSize: 11,
  height: 1.35,
  fontFamily: 'monospace',
  fontFamilyFallback: <String>['Menlo', 'Courier New', 'Courier'],
);

/// A boxed container for payloads and state trees.
Widget inspectorBox({required Widget child}) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(8),
  decoration: BoxDecoration(color: InspectorColors.card, borderRadius: BorderRadius.circular(6)),
  child: child,
);

/// A small uppercase section label, optionally with a trailing copy button.
Widget inspectorLabel(String text, {VoidCallback? onCopy}) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Row(
    children: <Widget>[
      Flexible(
        child: Builder(
          builder: (context) => Text(
            text,
            style: TextStyle(
              color: InspectorColors.accentOf(context),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
      if (onCopy != null) ...<Widget>[
        const SizedBox(width: 6),
        InkWell(
          onTap: onCopy,
          borderRadius: BorderRadius.circular(4),
          child: const Padding(
            padding: EdgeInsets.all(2),
            child: Icon(Icons.copy, size: 13, color: Colors.white38),
          ),
        ),
      ],
    ],
  ),
);

/// A compact text + icon action, e.g. "Clear".
Widget inspectorTextAction(String label, IconData icon, VoidCallback onTap) => InkWell(
  onTap: onTap,
  borderRadius: BorderRadius.circular(4),
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: Colors.white54),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    ),
  ),
);

/// A monospace `path:line` chip used for source locations.
Widget inspectorSourceLine(IconData icon, String location) => Padding(
  padding: const EdgeInsets.only(top: 5),
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    decoration: BoxDecoration(
      color: InspectorColors.sunken,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 13, color: InspectorColors.link),
        const SizedBox(width: 6),
        Expanded(
          child: SelectableText(
            location,
            style: inspectorMono.copyWith(color: InspectorColors.linkText, fontSize: 9),
          ),
        ),
      ],
    ),
  ),
);

/// A labelled box: [inspectorLabel] over [inspectorBox], with the label's copy
/// button wired to [copyValue] (hidden when it is `null`).
Widget inspectorField(String label, {required Widget child, Object? copyValue}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: <Widget>[
    inspectorLabel(label, onCopy: copyValue == null ? null : () => snoopCopy(copyValue)),
    inspectorBox(child: child),
  ],
);

/// An em dash standing in for a field that is present but empty.
const Widget inspectorAbsent = Text('—', style: TextStyle(color: Colors.white38, fontSize: 11));

/// A dot-separated metadata line, e.g. `12:04:31.882 · 214 ms · badResponse`.
/// Empty parts are dropped.
Widget inspectorMeta(List<String> parts) => Text(
  parts.where((p) => p.isNotEmpty).join('  ·  '),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: const TextStyle(color: Colors.white38, fontSize: 10),
);

/// The full-height message a tab shows before anything was recorded.
Widget inspectorEmpty(String title, {String? message, IconData? icon}) => Center(
  child: SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 32, color: Colors.white24),
          const SizedBox(height: 10),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        if (message != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
        ],
      ],
    ),
  ),
);

/// The quiet line a tab shows when its search or filter excludes everything.
Widget inspectorNoMatches(String label) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
  child: Center(
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white38, fontSize: 12),
    ),
  ),
);

/// A compact icon button for toolbars. A `null` [onTap] reads disabled.
Widget inspectorGlyph({
  required IconData icon,
  required String tooltip,
  VoidCallback? onTap,
  bool active = false,
  Key? key,
}) => Builder(
  key: key,
  builder: (context) => IconButton(
    visualDensity: VisualDensity.compact,
    onPressed: onTap,
    tooltip: tooltip,
    iconSize: 19,
    color: active ? InspectorColors.accentOf(context) : Colors.white70,
    disabledColor: Colors.white24,
    style: active ? IconButton.styleFrom(backgroundColor: InspectorColors.card) : null,
    icon: Icon(icon),
  ),
);

/// A small colored badge: an HTTP status, a log level, a navigation action.
class InspectorTag extends StatelessWidget {
  /// Creates a badge reading [label] in [color].
  const InspectorTag(this.label, {required this.color, super.key});

  /// The badge text.
  final String label;

  /// Text color; the fill is a translucent wash of it.
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    padding: const EdgeInsets.symmetric(vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
    ),
  );
}

/// One row in a tab's list: a leading badge, a title, a quiet second line, an
/// optional trailing figure, and a chevron when it drills in.
class InspectorRow extends StatelessWidget {
  /// Creates the row.
  const InspectorRow({
    required this.title,
    this.onTap,
    this.onLongPress,
    this.showChevron = true,
    this.leading,
    this.subtitle,
    this.trailing,
    super.key,
  });

  /// The main line, pre-styled so a caller can color part of it.
  final Widget title;

  /// Runs on tap. `null` makes the row inert.
  final VoidCallback? onTap;

  /// Runs on long-press, e.g. to copy the record.
  final VoidCallback? onLongPress;

  /// Whether a tappable row shows a chevron (it drills into a detail page).
  final bool showChevron;

  /// A status badge or dot.
  final Widget? leading;

  /// One quiet line under [title].
  final Widget? subtitle;

  /// A figure on the trailing edge, before the chevron.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    onLongPress: onLongPress,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DefaultTextStyle.merge(
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  child: title,
                ),
                if (subtitle != null) ...<Widget>[const SizedBox(height: 2), subtitle!],
              ],
            ),
          ),
          ?trailing,
          if (onTap != null && showChevron) ...<Widget>[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: Colors.white38),
          ],
        ],
      ),
    ),
  );
}

/// A detail screen pushed inside the inspector sheet: a back button, the
/// record's name, actions on it, and a scrolling body.
class InspectorDetailPage extends StatelessWidget {
  /// Creates the page.
  const InspectorDetailPage({
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    super.key,
  });

  /// What was drilled into.
  final String title;

  /// Toolbar actions on the record.
  final List<Widget> actions;

  /// The body.
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: InspectorColors.panel,
    body: SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 48,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 4),
                inspectorGlyph(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                ...actions,
                const SizedBox(width: 4),
              ],
            ),
          ),
          const Divider(height: 1, color: InspectorColors.divider),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

/// `HH:mm:ss.SSS`.
String inspectorTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}

/// Pretty-prints [value] as indented JSON, falling back to `toString()` for
/// values that can't be encoded.
String inspectorPretty(Object? value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on Object {
    return '$value';
  }
}

/// Copies [value] (pretty-printed unless it is a string) to the clipboard and
/// echoes it to the console.
///
/// The app can only reach the device clipboard, not the host machine's, so
/// the console echo lets you copy the text from the terminal running
/// `flutter run`. Long lines are chunked so logcat doesn't truncate them.
void snoopCopy(Object? value) {
  final text = value is String ? value : inspectorPretty(value);
  Clipboard.setData(ClipboardData(text: text)).ignore();
  if (!kDebugMode) return;
  const chunk = 3500;
  debugPrint('╭───────── INSPECTOR COPY ─────────');
  for (final line in text.split('\n')) {
    for (var i = 0; i < line.length || i == 0; i += chunk) {
      debugPrint(line.substring(i, i + chunk < line.length ? i + chunk : line.length));
    }
  }
  debugPrint('╰──────────────────────────────────');
}

/// A compact search field.
class InspectorSearchField extends StatelessWidget {
  /// Creates a search field.
  const InspectorSearchField({
    required this.controller,
    required this.hint,
    this.autofocus = false,
    super.key,
  });

  /// Holds the query.
  final TextEditingController controller;

  /// Whether the field takes focus when first shown.
  final bool autofocus;

  /// Placeholder text.
  final String hint;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        autofocus: autofocus,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
          prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white38),
          prefixIconConstraints: const BoxConstraints(minWidth: 30),
          suffixIcon: value.text.isEmpty
              ? null
              : GestureDetector(
                  onTap: controller.clear,
                  child: const Icon(Icons.close, size: 14, color: Colors.white38),
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 28),
          filled: true,
          fillColor: InspectorColors.card,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    ),
  );
}

/// A compact pill-style segmented control.
class InspectorSegmented<T> extends StatelessWidget {
  /// Creates a segmented control.
  const InspectorSegmented({
    required this.value,
    required this.segments,
    required this.onChanged,
    this.expand = false,
    super.key,
  });

  /// Whether the segments share the full width equally.
  final bool expand;

  /// The selected value.
  final T value;

  /// `(value, label)` pairs.
  final List<(T, String)> segments;

  /// Called with the tapped value.
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(color: InspectorColors.card, borderRadius: BorderRadius.circular(6)),
    child: Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[
        for (final (segment, label) in segments)
          if (expand)
            Expanded(child: _segment(context, segment, label))
          else
            _segment(context, segment, label),
      ],
    ),
  );

  Widget _segment(BuildContext context, T segment, String label) {
    final selected = segment == value;
    return InkWell(
      onTap: selected ? null : () => onChanged(segment),
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? InspectorColors.accentOf(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? InspectorColors.onAccentOf(context) : Colors.white54,
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
