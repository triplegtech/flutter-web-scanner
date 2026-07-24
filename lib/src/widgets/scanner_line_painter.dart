import 'package:flutter/material.dart';

class ScannerLinePainter extends CustomPainter {
  final double position;

  ScannerLinePainter({required this.position});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const double horizontalMargin = 8;

    canvas.drawLine(
      Offset(horizontalMargin, position),
      Offset(size.width - horizontalMargin, position),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant ScannerLinePainter oldDelegate) =>
      oldDelegate.position != position;
}
