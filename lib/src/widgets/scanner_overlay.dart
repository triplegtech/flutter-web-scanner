import 'package:flutter/widgets.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/scanner_overlay_style.dart';
import 'package:omni_qrcode_barcode_web_reader/src/widgets/scanner_line_painter.dart';
import 'package:omni_qrcode_barcode_web_reader/src/widgets/scanner_overlay_shape.dart';

/// Dims the preview outside a framing window and animates a scan line inside
/// it.
///
/// Replaces the two duplicated overlay widgets from 1.x; the shape comes
/// entirely from [ScannerOverlayStyle].
class ScannerOverlay extends StatefulWidget {
  const ScannerOverlay({super.key, required this.style});

  final ScannerOverlayStyle style;

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.style.scanLineDuration,
  );

  late final Animation<double> _sweep = Tween<double>(
    begin: -0.075,
    end: 0.80,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ScannerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.style.scanLineDuration != oldWidget.style.scanLineDuration) {
      _controller.duration = widget.style.scanLineDuration;
    }
    if (widget.style.showScanLine != oldWidget.style.showScanLine) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.style.showScanLine) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Sized from the widget's own constraints rather than from
        // MediaQuery, so the overlay stays aligned with the preview when the
        // scanner is not full-bleed.
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final cutOutWidth = available * style.cutOutWidthFactor;

        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: ShapeDecoration(
                shape: ScannerOverlayShape(
                  cutOutWidth: cutOutWidth,
                  cutOutHeight: style.cutOutHeight,
                  cutOutBottomOffset: style.cutOutBottomOffset,
                  borderColor: style.borderColor,
                  borderLength: style.borderLength,
                  borderWidth: style.borderWidth,
                  borderRadius: style.borderRadius,
                  overlayColor: style.overlayColor,
                ),
              ),
            ),
            if (style.showScanLine)
              IgnorePointer(
                child: Center(
                  // ScannerOverlayShape lifts the cut-out by
                  // cutOutBottomOffset. Without matching that translation the
                  // sweep line drifts below the frame it is supposed to be
                  // inside — visible in 1.x whenever the offset was non-zero.
                  child: Transform.translate(
                    offset: Offset(0, -style.cutOutBottomOffset),
                    child: SizedBox(
                      width: cutOutWidth,
                      height: style.cutOutHeight,
                      child: AnimatedBuilder(
                        animation: _sweep,
                        builder: (context, _) => CustomPaint(
                          painter: ScannerLinePainter(
                            position: _sweep.value * style.cutOutHeight,
                            color: style.scanLineColor,
                            strokeWidth: style.scanLineWidth,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
