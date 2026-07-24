import 'package:flutter/material.dart';
import 'package:omni_qrcode_barcode_web_reader/src/widgets/scanner_line_painter.dart';
import 'package:omni_qrcode_barcode_web_reader/src/widgets/scanner_overlay_shape.dart';

class QrCodeOverlayWidget extends StatefulWidget {
  const QrCodeOverlayWidget({super.key});

  @override
  State<QrCodeOverlayWidget> createState() => _QrCodeOverlayWidgetState();
}

class _QrCodeOverlayWidgetState extends State<QrCodeOverlayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  final double cutOutHeight = 330;
  final double cutOutWidthFactor = 0.85;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: -0.075, end: 0.80).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
              borderLength: 30,
              borderWidth: 8,
              borderRadius: 10,
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
                  return CustomPaint(
                    painter: ScannerLinePainter(position: y),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
