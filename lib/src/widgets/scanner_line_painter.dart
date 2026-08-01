import 'package:flutter/widgets.dart';

/// Draws the horizontal sweep line inside the overlay cut-out.
class ScannerLinePainter extends CustomPainter {
  const ScannerLinePainter({
    required this.position,
    required this.color,
    this.strokeWidth = 3,
    this.horizontalMargin = 8,
  });

  /// Vertical offset of the line within the cut-out, in logical pixels.
  final double position;

  final Color color;
  final double strokeWidth;

  /// Inset from each edge, so the line reads as inside the frame rather than
  /// touching the corner brackets.
  final double horizontalMargin;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(horizontalMargin, position),
      Offset(size.width - horizontalMargin, position),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant ScannerLinePainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
