import 'package:flutter/material.dart';

/// A scrolling demo screen with a title and a list of children.
class DemoPage extends StatelessWidget {
  /// Creates a demo screen.
  const DemoPage({required this.title, required this.children, super.key});

  /// The app bar title.
  final String title;

  /// What the screen shows, top to bottom.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(padding: const EdgeInsets.all(16), children: children),
  );
}

/// A section heading with an optional explanation under it.
class DemoSection extends StatelessWidget {
  /// Creates a heading.
  const DemoSection(this.title, {this.hint, super.key});

  /// The heading.
  final String title;

  /// A short line under the heading.
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (hint != null) Text(hint!, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

/// A row of buttons that wraps on narrow screens.
class DemoButtons extends StatelessWidget {
  /// Creates the row from [buttons], a label to callback map.
  const DemoButtons(this.buttons, {super.key});

  /// Button labels and what they do. A null callback disables the button.
  final Map<String, VoidCallback?> buttons;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (final entry in buttons.entries)
        FilledButton.tonal(onPressed: entry.value, child: Text(entry.key)),
    ],
  );
}

/// The outcome of the last action, so a tap visibly does something.
class DemoStatus extends StatelessWidget {
  /// Creates a status line.
  const DemoStatus(this.text, {super.key});

  /// What happened.
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(text, key: const Key('status'), style: Theme.of(context).textTheme.bodyMedium),
  );
}
