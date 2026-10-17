import 'package:flutter/widgets.dart';

/// Snoop's own stroke icons, drawn from the SVGs in `assets/` so the package
/// needs no SVG dependency. Like [Icon], they take their color and size from
/// the ambient [IconTheme] unless given.
class SnoopIcon extends StatelessWidget {
  /// The bug, from `assets/bug.svg`: the bubble and panel header.
  const SnoopIcon.bug({this.size, this.color, super.key}) : _glyph = _Glyph.bug;

  /// Two stacked sheets, from `assets/copy.svg`: copy actions.
  const SnoopIcon.copy({this.size, this.color, super.key}) : _glyph = _Glyph.copy;

  /// A magnifier, from `assets/search.svg`: the search buttons and fields.
  const SnoopIcon.search({this.size, this.color, super.key}) : _glyph = _Glyph.search;

  /// A bin, from `assets/trash.svg`: clear actions.
  const SnoopIcon.trash({this.size, this.color, super.key}) : _glyph = _Glyph.trash;

  /// Angle brackets, from `assets/code.svg`: source locations.
  const SnoopIcon.code({this.size, this.color, super.key}) : _glyph = _Glyph.code;

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

/// An SVG on a 24×24 viewBox, split into its outline and detail strokes. Both
/// draw in the full color so the glyphs match the Material icons beside them.
enum _Glyph {
  bug,
  copy,
  search,
  trash,
  code;

  Path get outline => switch (this) {
    // Head and body.
    _Glyph.bug => _bugBody,
    // Front sheet.
    _Glyph.copy => _copyFront,
    // Lens.
    _Glyph.search => _searchLens,
    // Lid and bin.
    _Glyph.trash => _trashBin,
    // Both brackets.
    _Glyph.code => _codeBrackets,
  };

  Path get details => switch (this) {
    // Legs, antennae and the center seam.
    _Glyph.bug => _bugLegs,
    // Back sheet.
    _Glyph.copy => _copyBack,
    // Handle.
    _Glyph.search => _searchHandle,
    // Ribs and the lid's handle.
    _Glyph.trash => _trashDetails,
    // Slash.
    _Glyph.code => _codeSlash,
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

final Path _searchLens = Path()
  ..addOval(Rect.fromCircle(center: const Offset(11.5, 11.5), radius: 9.5));

final Path _searchHandle = Path()
  ..moveTo(18.2173, 18.2178)
  ..lineTo(21.9999, 22.0004);

final Path _trashBin = Path()
  ..moveTo(20.5001, 6)
  ..lineTo(3.5, 6)
  ..moveTo(18.8334, 8.5)
  ..lineTo(18.3735, 15.3991)
  ..cubicTo(18.1965, 18.054, 18.108, 19.3815, 17.243, 20.1907)
  ..cubicTo(16.378, 21, 15.0476, 21, 12.3868, 21)
  ..lineTo(11.6134, 21)
  ..cubicTo(8.9526, 21, 7.6222, 21, 6.75719, 20.1907)
  ..cubicTo(5.89218, 19.3815, 5.80368, 18.054, 5.62669, 15.3991)
  ..lineTo(5.16675, 8.5);

final Path _trashDetails = Path()
  ..moveTo(9.5, 11)
  ..lineTo(10, 16)
  ..moveTo(14.5, 11)
  ..lineTo(14, 16)
  ..moveTo(6.5, 6)
  ..cubicTo(6.55588, 6, 6.58382, 6, 6.60915, 5.99936)
  ..cubicTo(7.43259, 5.97849, 8.15902, 5.45491, 8.43922, 4.68032)
  ..cubicTo(8.44784, 4.65649, 8.45667, 4.62999, 8.47434, 4.57697)
  ..lineTo(8.57143, 4.28571)
  ..cubicTo(8.65431, 4.03708, 8.69575, 3.91276, 8.75071, 3.8072)
  ..cubicTo(8.97001, 3.38607, 9.37574, 3.09364, 9.84461, 3.01877)
  ..cubicTo(9.96213, 3, 10.0932, 3, 10.3553, 3)
  ..lineTo(13.6447, 3)
  ..cubicTo(13.9068, 3, 14.0379, 3, 14.1554, 3.01877)
  ..cubicTo(14.6243, 3.09364, 15.03, 3.38607, 15.2493, 3.8072)
  ..cubicTo(15.3043, 3.91276, 15.3457, 4.03708, 15.4286, 4.28571)
  ..lineTo(15.5257, 4.57697)
  ..cubicTo(15.5433, 4.62992, 15.5522, 4.65651, 15.5608, 4.68032)
  ..cubicTo(15.841, 5.45491, 16.5674, 5.97849, 17.3909, 5.99936)
  ..cubicTo(17.4162, 6, 17.4441, 6, 17.5, 6);

final Path _codeBrackets = Path()
  ..moveTo(17, 7.82959)
  ..lineTo(18.6965, 9.35641)
  ..cubicTo(20.239, 10.7447, 21.0103, 11.4389, 21.0103, 12.3296)
  ..cubicTo(21.0103, 13.2203, 20.239, 13.9145, 18.6965, 15.3028)
  ..lineTo(17, 16.8296)
  ..moveTo(7.00005, 7.82959)
  ..lineTo(5.30358, 9.35641)
  ..cubicTo(3.76102, 10.7447, 2.98975, 11.4389, 2.98975, 12.3296)
  ..cubicTo(2.98975, 13.2203, 3.76102, 13.9145, 5.30358, 15.3028)
  ..lineTo(7.00005, 16.8296);

final Path _codeSlash = Path()
  ..moveTo(13.9868, 5)
  ..lineTo(10.0132, 19.8297);

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
    canvas.drawPath(glyph.outline, paint);
    canvas.drawPath(glyph.details, paint);
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
