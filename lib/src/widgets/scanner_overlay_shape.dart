import 'dart:math';

import 'package:flutter/material.dart';

/// Dims everything outside a framing window and draws a corner bracket at each
/// of its corners.
class ScannerOverlayShape extends ShapeBorder {
  ScannerOverlayShape({
    this.borderColor = Colors.red,
    this.borderWidth = 3.0,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 50),
    this.borderRadius = 0,
    this.borderLength = 40,
    double? cutOutSize,
    double? cutOutWidth,
    double? cutOutHeight,
    this.cutOutBottomOffset = 0,
  })  : cutOutWidth = cutOutWidth ?? cutOutSize ?? 250,
        cutOutHeight = cutOutHeight ?? cutOutSize ?? 250 {
    assert(
      borderLength <=
          min(this.cutOutWidth, this.cutOutHeight) / 2 + borderWidth * 2,
      "Border can't be larger than ${min(this.cutOutWidth, this.cutOutHeight) / 2 + borderWidth * 2}",
    );
    assert(
        (cutOutWidth == null && cutOutHeight == null) ||
            (cutOutSize == null && cutOutWidth != null && cutOutHeight != null),
        'Use only cutOutWidth and cutOutHeight or only cutOutSize');
  }

  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutWidth;
  final double cutOutHeight;
  final double cutOutBottomOffset;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  /// The framing window, in the same coordinates [paint] draws in.
  RRect _window(Rect rect) {
    final borderOffset = borderWidth / 2;
    final width =
        cutOutWidth < rect.width ? cutOutWidth : rect.width - borderOffset;
    final height =
        cutOutHeight < rect.height ? cutOutHeight : rect.height - borderOffset;

    return RRect.fromRectAndRadius(
      Rect.fromLTWH(
        rect.left + rect.width / 2 - width / 2 + borderOffset,
        -cutOutBottomOffset +
            rect.top +
            rect.height / 2 -
            height / 2 +
            borderOffset,
        width - borderOffset * 2,
        height - borderOffset * 2,
      ),
      Radius.circular(borderRadius),
    );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final window = _window(rect);

    // One fill, no offscreen surface.
    //
    // The obvious way to punch a window out of a filled rect is to wrap both
    // in a saveLayer and erase with BlendMode.dstOut, which is what this
    // painted before. CanvasKit answers a saveLayer by allocating a
    // viewport-sized RGBA texture, rendering into it and compositing it back
    // — on a phone that is several megabytes of traffic per paint, and it was
    // the single most expensive thing the overlay did. Subtracting the window
    // from the rect up front is the same picture from one drawPath.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      Path()..addRRect(window),
    );

    canvas.drawPath(outside, Paint()..color = overlayColor);

    _paintBrackets(
      canvas,
      window,
      outside,
      // Kept as it was, including comparing cutOutHeight against itself: the
      // constructor's assert already rejects everything this would catch, so
      // the branch is unreachable and correcting it would be a change with no
      // way to observe it.
      borderLength > min(cutOutHeight, cutOutHeight) / 2 + borderWidth * 2
          ? rect.width / 4
          : borderLength,
    );
  }

  /// Draws the four corner brackets.
  ///
  /// Each bracket is stroked as a whole rounded rectangle and becomes the
  /// familiar L only because everything inside the window is taken away again.
  /// Clipping to [outside] — the same subtracted path the dimming is filled
  /// with — removes exactly the pixels the old dstOut pass removed, so the
  /// brackets keep their shape without the layer that pass needed.
  void _paintBrackets(
    Canvas canvas,
    RRect window,
    Path outside,
    double length,
  ) {
    final paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final radius = Radius.circular(borderRadius);

    canvas
      ..save()
      ..clipPath(outside)
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          window.right - length,
          window.top,
          window.right,
          window.top + length,
          topRight: radius,
        ),
        paint,
      )
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          window.left,
          window.top,
          window.left + length,
          window.top + length,
          topLeft: radius,
        ),
        paint,
      )
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          window.right - length,
          window.bottom - length,
          window.right,
          window.bottom,
          bottomRight: radius,
        ),
        paint,
      )
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          window.left,
          window.bottom - length,
          window.left + length,
          window.bottom,
          bottomLeft: radius,
        ),
        paint,
      )
      ..restore();
  }

  @override
  ShapeBorder scale(double t) => ScannerOverlayShape(
        borderColor: borderColor,
        borderWidth: borderWidth * t,
        overlayColor: overlayColor,
        borderRadius: borderRadius * t,
        borderLength: borderLength * t,
        cutOutWidth: cutOutWidth * t,
        cutOutHeight: cutOutHeight * t,
        cutOutBottomOffset: cutOutBottomOffset * t,
      );

  // ShapeBorder does not define equality, so without this a shape rebuilt from
  // an unchanged style still compares unequal to the one it replaces and
  // ShapeDecoration repaints the whole dimmed area for nothing.
  @override
  bool operator ==(Object other) =>
      other is ScannerOverlayShape &&
      other.borderColor == borderColor &&
      other.borderWidth == borderWidth &&
      other.overlayColor == overlayColor &&
      other.borderRadius == borderRadius &&
      other.borderLength == borderLength &&
      other.cutOutWidth == cutOutWidth &&
      other.cutOutHeight == cutOutHeight &&
      other.cutOutBottomOffset == cutOutBottomOffset;

  @override
  int get hashCode => Object.hash(
        borderColor,
        borderWidth,
        overlayColor,
        borderRadius,
        borderLength,
        cutOutWidth,
        cutOutHeight,
        cutOutBottomOffset,
      );
}
