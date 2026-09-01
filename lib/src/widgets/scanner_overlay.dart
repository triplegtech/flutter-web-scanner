import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_web_scanner/src/models/scanner_overlay_style.dart';
import 'package:flutter_web_scanner/src/widgets/scanner_overlay_shape.dart';

/// Inset of the sweep line from each side of the window, so it reads as inside
/// the frame rather than running into the corner brackets.
const double _scanLineInset = 8;

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

  /// Runs 0 → 1 across the framing window, edge to edge.
  ///
  /// 1.x swept -0.075 → 0.80 of the cut-out's height, which started the line
  /// outside the window and stopped it a fifth of the way short of the bottom.
  late final Animation<double> _sweep = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

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
        final screen = MediaQuery.sizeOf(context);
        final size = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : screen.width,
          constraints.hasBoundedHeight ? constraints.maxHeight : screen.height,
        );

        final cutOut = style.cutOutSizeFor(size);
        final shape = ScannerOverlayShape(
          cutOutWidth: cutOut.width,
          cutOutHeight: cutOut.height,
          cutOutBottomOffset: style.cutOutBottomOffset,
          borderColor: style.borderColor,
          borderLength: style.borderLength,
          borderWidth: style.borderWidth,
          borderRadius: style.borderRadius,
          overlayColor: style.overlayColor,
        );

        // The one place the window's geometry is decided. Positioning the line
        // from the shape's own answer is what keeps the two from drifting when
        // the window is clamped to fit a short preview.
        final window = shape.windowFor(Offset.zero & size).outerRect;
        final travel = window.height - style.scanLineWidth;

        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(decoration: ShapeDecoration(shape: shape)),
            if (style.showScanLine)
              Positioned.fromRect(
                rect: window,
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: AnimatedBuilder(
                      animation: _sweep,
                      // Built once and handed back to every tick. The line
                      // itself never changes, only where it sits, so
                      // rebuilding it inside the builder would throw away the
                      // raster the boundary below is holding.
                      child: RepaintBoundary(
                        child: _ScanLine(
                          color: style.scanLineColor,
                          thickness: style.scanLineWidth,
                        ),
                      ),
                      // Travelling the line's own thickness short of the full
                      // height is what lands its trailing edge on the window's
                      // bottom edge rather than past it.
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, _sweep.value * math.max(0, travel)),
                        child: child,
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

/// The sweeping line, rasterised once and thereafter only moved.
///
/// Painting this with a [CustomPainter] meant re-rasterising a cut-out-sized
/// picture on each of the sixty frames a second the sweep runs for, for the
/// whole time the camera is open. As an ordinary box behind a
/// [RepaintBoundary] it is rasterised once and the animation above it changes
/// nothing but a layer's transform, which is work the compositor already does.
class _ScanLine extends StatelessWidget {
  const _ScanLine({required this.color, required this.thickness});

  final Color color;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _scanLineInset),
      child: SizedBox(
        width: double.infinity,
        height: thickness,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            // Reproduces the round stroke cap the line had while it was drawn
            // as a stroked segment.
            borderRadius: BorderRadius.circular(thickness / 2),
          ),
        ),
      ),
    );
  }
}
