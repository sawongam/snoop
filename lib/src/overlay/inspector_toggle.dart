import 'package:flutter/material.dart';
import 'package:snoop/src/bloc/bloc_inspector_registry.dart';
import 'package:snoop/src/widgets/inspector_shared.dart';
import 'package:snoop/src/widgets/live_builder.dart';

/// Reads a value, with access to the app's [BuildContext] (e.g. for
/// `context.read<ThemeCubit>()`).
typedef SnoopValueGetter<T> = T Function(BuildContext context);

/// Applies a value chosen in the inspector.
typedef SnoopValueSetter<T> = void Function(BuildContext context, T value);

/// Runs a quick action.
typedef SnoopAction = void Function(BuildContext context);

/// A custom quick action shown in a bar at the top of the inspector panel,
/// for flipping app settings while debugging (theme, locale, feature flags,
/// fake login, …).
///
/// The callbacks receive a [BuildContext] below the inspector overlay, so
/// anything provided above `MaterialApp` (blocs, repositories) is reachable.
///
/// The bar re-reads every value after a tap, whenever any bloc emits, and
/// whenever [listenable] notifies. So values backed by a bloc state or a
/// [Listenable] you pass stay in sync without extra wiring.
///
/// ```dart
/// SnoopOverlay(
///   toggles: [
///     SnoopToggle.action(label: 'Log out', icon: Icons.logout, onTap: (c) => ...),
///     SnoopToggle.switcher(
///       label: 'Mock API',
///       value: (_) => flags.mockApi,
///       onChanged: (_, v) => flags.mockApi = v,
///     ),
///     SnoopSegmentedToggle<ThemeMode>(
///       label: 'Theme',
///       icon: Icons.brightness_6_outlined,
///       segments: const [(ThemeMode.light, 'Light'), (ThemeMode.dark, 'Dark')],
///       value: (c) => c.read<ThemeCubit>().state,
///       onChanged: (c, mode) => c.read<ThemeCubit>().set(mode),
///     ),
///   ],
///   child: child!,
/// )
/// ```
sealed class SnoopToggle {
  const SnoopToggle({required this.label, this.icon, this.listenable});

  /// A button that runs [onTap].
  const factory SnoopToggle.action({
    required String label,
    required SnoopAction onTap,
    IconData? icon,
  }) = SnoopActionToggle;

  /// An on/off switch.
  const factory SnoopToggle.switcher({
    required String label,
    required SnoopValueGetter<bool> value,
    required SnoopValueSetter<bool> onChanged,
    IconData? icon,
    Listenable? listenable,
  }) = SnoopSwitchToggle;

  /// Text shown next to the control (and as its tooltip when [icon] is set).
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Extra source of change that should refresh the control's value.
  final Listenable? listenable;
}

/// A button that runs [onTap]. See [SnoopToggle].
final class SnoopActionToggle extends SnoopToggle {
  /// Creates an action.
  const SnoopActionToggle({required super.label, required this.onTap, super.icon});

  /// Runs when the button is tapped.
  final SnoopAction onTap;
}

/// An on/off switch. See [SnoopToggle].
final class SnoopSwitchToggle extends SnoopToggle {
  /// Creates a switch.
  const SnoopSwitchToggle({
    required super.label,
    required this.value,
    required this.onChanged,
    super.icon,
    super.listenable,
  });

  /// Reads whether the switch is on.
  final SnoopValueGetter<bool> value;

  /// Applies a new value.
  final SnoopValueSetter<bool> onChanged;
}

/// A single-choice segmented control. See [SnoopToggle].
final class SnoopSegmentedToggle<T> extends SnoopToggle {
  /// Creates a segmented control.
  const SnoopSegmentedToggle({
    required super.label,
    required this.segments,
    required this.value,
    required this.onChanged,
    super.icon,
    super.listenable,
  });

  /// `(value, label)` pairs, in display order.
  final List<(T, String)> segments;

  /// Reads the selected value.
  final SnoopValueGetter<T> value;

  /// Applies a new value.
  final SnoopValueSetter<T> onChanged;

  // Typed trampolines: reading the generic fields through
  // SnoopSegmentedToggle<Object?> would fail the covariance check.
  Widget _build(BuildContext context, VoidCallback refresh) => InspectorSegmented<T>(
    value: value(context),
    segments: segments,
    onChanged: (v) {
      onChanged(context, v);
      refresh();
    },
  );
}

/// The horizontal bar of [SnoopToggle]s in the inspector panel.
class InspectorToggleBar extends StatefulWidget {
  /// Creates the bar.
  const InspectorToggleBar({required this.toggles, super.key});

  /// The toggles to show.
  final List<SnoopToggle> toggles;

  @override
  State<InspectorToggleBar> createState() => _InspectorToggleBarState();
}

class _InspectorToggleBarState extends State<InspectorToggleBar> {
  late Listenable _changes = _merge();

  Listenable _merge() => Listenable.merge(<Listenable?>[
    BlocInspectorRegistry.instance,
    for (final t in widget.toggles) t.listenable,
  ]);

  @override
  void didUpdateWidget(InspectorToggleBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.toggles != widget.toggles) _changes = _merge();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => LiveBuilder(
    listenable: _changes,
    builder: (context) => SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: widget.toggles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) => Center(child: _item(context, widget.toggles[i])),
      ),
    ),
  );

  Widget _item(BuildContext context, SnoopToggle toggle) {
    final Widget control = switch (toggle) {
      SnoopActionToggle(:final onTap) => inspectorTextAction(
        toggle.label,
        toggle.icon ?? Icons.play_arrow_rounded,
        () {
          onTap(context);
          _refresh();
        },
      ),
      SnoopSwitchToggle(:final value, :final onChanged) => SizedBox(
        height: 24,
        child: FittedBox(
          child: Switch(
            value: value(context),
            activeThumbColor: Colors.white,
            activeTrackColor: InspectorColors.accent,
            onChanged: (v) {
              onChanged(context, v);
              _refresh();
            },
          ),
        ),
      ),
      final SnoopSegmentedToggle<Object?> t => t._build(context, _refresh),
    };
    if (toggle is SnoopActionToggle) return control;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (toggle.icon != null)
          Tooltip(
            message: toggle.label,
            child: Icon(toggle.icon, size: 14, color: Colors.white38),
          )
        else
          Text(toggle.label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(width: 6),
        control,
      ],
    );
  }
}
