import 'package:flutter/material.dart';
import 'package:flutter_web_scanner_example/scanner_overlay_shape.dart';

class BarcodeOverlayWidget extends StatefulWidget {
  const BarcodeOverlayWidget({super.key});

  @override
  State<BarcodeOverlayWidget> createState() => _BarcodeOverlayWidgetState();
}

class _BarcodeOverlayWidgetState extends State<BarcodeOverlayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  final double cutOutHeight = 150;
  final double cutOutWidthFactor = 0.7;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: -0.075,
      end: 0.80,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final cutOutWidth = screenSize.width * cutOutWidthFactor;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: ShapeDecoration(
            shape: ScannerOverlayShape(
              cutOutWidth: cutOutWidth,
              cutOutHeight: cutOutHeight,
              cutOutBottomOffset: 20,
              borderColor: Colors.white,
              borderLength: 25,
              borderWidth: 8,
              borderRadius: 8,
              overlayColor: Colors.black.withOpacity(0.75),
            ),
          ),
        ),
        IgnorePointer(
          child: Center(
            child: SizedBox(
              width: cutOutWidth,
              height: cutOutHeight,
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  final y = _animation.value * cutOutHeight;
                  return CustomPaint(painter: _ScannerLinePainter(position: y));
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScannerLinePainter extends CustomPainter {
  final double position;

  _ScannerLinePainter({required this.position});

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
  bool shouldRepaint(covariant _ScannerLinePainter oldDelegate) =>
      oldDelegate.position != position;
}
