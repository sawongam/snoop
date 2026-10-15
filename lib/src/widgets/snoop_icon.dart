import 'package:flutter/widgets.dart';

/// Snoop's own stroke icons, drawn from the SVGs in `assets/` so the package
/// needs no SVG dependency. Like [Icon], they take their color and size from
/// the ambient [IconTheme] unless given.
class SnoopIcon extends StatelessWidget {
  /// The bug, from `assets/bug.svg`: the bubble and panel header.
  const SnoopIcon.bug({this.size, this.color, super.key}) : _glyph = _Glyph.bug;

  /// Two stacked sheets, from `assets/copy.svg`: copy actions.
  const SnoopIcon.copy({this.size, this.color, super.key}) : _glyph = _Glyph.copy;

  /// Width and height. Defaults to the [IconTheme]'s size, then 24.
  final double? size;

  /// Stroke color. Defaults to the [IconTheme]'s color.
  final Color? color;

  final _Glyph _glyph;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    final color = this.color ?? theme.color ?? const Color(0xFF000000);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GlyphPainter(_glyph, color)),
    );
  }
}

/// An SVG on a 24×24 viewBox, split into its full and half-opacity strokes.
enum _Glyph {
  bug,
  copy;

  Path get solid => switch (this) {
    // Head and body.
    _Glyph.bug => _bugBody,
    // Front sheet.
    _Glyph.copy => _copyFront,
  };

  Path get faded => switch (this) {
    // Legs, antennae and the center seam.
    _Glyph.bug => _bugLegs,
    // Back sheet.
    _Glyph.copy => _copyBack,
  };
}

final Path _bugBody = Path()
  ..moveTo(16.5, 8.27065)
  ..lineTo(16.5, 7.5)
  ..cubicTo(16.5, 5.01472, 14.4853, 3, 12, 3)
  ..cubicTo(9.51472, 3, 7.5, 5.01472, 7.5, 7.5)
  ..lineTo(7.5, 8.27065)
  ..moveTo(19, 11.9375)
  ..lineTo(19, 15)
  ..cubicTo(19, 18.866, 15.866, 22, 12, 22)
  ..cubicTo(8.13401, 22, 5, 18.866, 5, 15)
  ..lineTo(5, 11.9375)
  ..cubicTo(5, 9.76288, 6.76288, 8, 8.9375, 8)
  ..lineTo(15.0625, 8)
  ..cubicTo(17.2371, 8, 19, 9.76288, 19, 11.9375)
  ..close();

final Path _bugLegs = Path()
  ..moveTo(19, 14)
  ..lineTo(22, 14)
  ..moveTo(5, 14)
  ..lineTo(2, 14)
  ..moveTo(14.2905, 3.62571)
  ..lineTo(17, 2)
  ..moveTo(9.70947, 3.62569)
  ..lineTo(7, 2)
  ..moveTo(17.8003, 18.9202)
  ..lineTo(20.5002, 20.0001)
  ..moveTo(17.7798, 9.08789)
  ..lineTo(20.4999, 7.99984)
  ..moveTo(6.19971, 18.9202)
  ..lineTo(3.49987, 20.0001)
  ..moveTo(12, 22)
  ..lineTo(12, 15)
  ..moveTo(6.22021, 9.08789)
  ..lineTo(3.50018, 7.99988);

final Path _copyFront = Path()
  ..moveTo(6, 11)
  ..cubicTo(6, 8.17157, 6, 6.75736, 6.87868, 5.87868)
  ..cubicTo(7.75736, 5, 9.17157, 5, 12, 5)
  ..lineTo(15, 5)
  ..cubicTo(17.8284, 5, 19.2426, 5, 20.1213, 5.87868)
  ..cubicTo(21, 6.75736, 21, 8.17157, 21, 11)
  ..lineTo(21, 16)
  ..cubicTo(21, 18.8284, 21, 20.2426, 20.1213, 21.1213)
  ..cubicTo(19.2426, 22, 17.8284, 22, 15, 22)
  ..lineTo(12, 22)
  ..cubicTo(9.17157, 22, 7.75736, 22, 6.87868, 21.1213)
  ..cubicTo(6, 20.2426, 6, 18.8284, 6, 16)
  ..lineTo(6, 11)
  ..close();

final Path _copyBack = Path()
  ..moveTo(6, 19)
  ..cubicTo(4.34315, 19, 3, 17.6569, 3, 16)
  ..lineTo(3, 10)
  ..cubicTo(3, 6.22876, 3, 4.34315, 4.17157, 3.17157)
  ..cubicTo(5.34315, 2, 7.22876, 2, 11, 2)
  ..lineTo(15, 2)
  ..cubicTo(16.6569, 2, 18, 3.34315, 18, 5);

/// Paints a [_Glyph] scaled from its 24×24 viewBox to the canvas.
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawPath(glyph.solid, paint);
    canvas.drawPath(glyph.faded, paint..color = color.withValues(alpha: color.a * 0.5));
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
