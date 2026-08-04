import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_mode.dart';

/// Appearance of the framing overlay drawn over the camera preview.
///
/// 1.x shipped two near-identical overlay widgets that differed only in four
/// hardcoded numbers and could not be customised at all. One parameterised
/// style replaces both.
///
/// The measurements are the ones the OMNI mobile app draws over its own
/// scanner, so someone moving between the app and the web reader is framed by
/// the same overlay. Both modes share every colour and bracket measurement;
/// only the shape of the window differs, and [ScannerOverlayStyle.forMode] is
/// what picks it.
class ScannerOverlayStyle {
  const ScannerOverlayStyle({
    this.cutOutWidthFactor = 0.7,
    this.cutOutHeight = 150,
    this.squareCutOut = false,
    this.cutOutBottomOffset = 20,
    this.borderColor = const Color(0xFFFFFFFF),
    this.borderLength = 25,
    this.borderWidth = 8,
    this.borderRadius = 8,
    this.overlayColor = const Color(0xBF000000),
    this.scanLineColor = const Color(0xFFF44336),
    this.scanLineWidth = 3,
    this.showScanLine = true,
    this.scanLineDuration = const Duration(seconds: 2),
  })  : assert(
          cutOutWidthFactor > 0 && cutOutWidthFactor <= 1,
          'cutOutWidthFactor must be within (0, 1]',
        ),
        assert(cutOutHeight > 0, 'cutOutHeight must be positive');

  /// Cut-out width as a fraction of the available width.
  ///
  /// Under [squareCutOut] it is a fraction of the preview's *shorter* axis
  /// instead, since that is the one the window has to fit.
  final double cutOutWidthFactor;

  /// Cut-out height in logical pixels. Unused when [squareCutOut] is set.
  final double cutOutHeight;

  /// Frames the preview in a square rather than a wide, short band.
  ///
  /// A 1D barcode is a band and wants a band-shaped window; a QR code is
  /// square and wants a square one. Deriving the side from the preview rather
  /// than taking a fixed [cutOutHeight] is what keeps it square on a wide
  /// desktop preview, where a fixed height would read as a rectangle again.
  final bool squareCutOut;

  /// Shifts the cut-out up from centre, leaving room for instructions below.
  final double cutOutBottomOffset;

  final Color borderColor;

  /// Length of each corner bracket.
  final double borderLength;

  final double borderWidth;
  final double borderRadius;

  /// Colour of the dimmed area outside the cut-out.
  ///
  /// Rendered at exactly the alpha given here. Until 2.0.x the shape wrapped
  /// its paint in a `saveLayer` and handed the same colour to both the layer
  /// and the fill, so the alpha was applied twice and a nominal `0xBF` reached
  /// the screen as `0x8F`. The default is the value that was actually visible,
  /// not the one that used to be written down.
  final Color overlayColor;

  final Color scanLineColor;
  final double scanLineWidth;

  /// Whether to animate a sweeping line inside the cut-out.
  final bool showScanLine;

  /// One full sweep of the scan line.
  final Duration scanLineDuration;

  /// Defaults shaped for [mode].
  ///
  /// The two differ in one thing only: a 1D barcode is framed in the wide,
  /// short band the mobile app uses, and everything 2D is framed in a square
  /// with the same brackets, colours and sweep.
  factory ScannerOverlayStyle.forMode(ScanMode mode) => mode.isLinear
      ? const ScannerOverlayStyle()
      : const ScannerOverlayStyle(squareCutOut: true);

  /// The window's size inside a preview measuring [available].
  ///
  /// The one place the window's dimensions are decided, so that the shape and
  /// anything drawn inside it read the same numbers.
  Size cutOutSizeFor(Size available) {
    if (!squareCutOut) {
      return Size(available.width * cutOutWidthFactor, cutOutHeight);
    }

    // Measured against the shorter axis. Taking the width would hand the shape
    // a window taller than the preview on any landscape viewport, and the
    // shape answers that by clamping the height alone — which is to say, by
    // turning the square back into the rectangle it was asked not to be.
    final side =
        math.min(available.width, available.height) * cutOutWidthFactor;
    return Size(side, side);
  }

  ScannerOverlayStyle copyWith({
    double? cutOutWidthFactor,
    double? cutOutHeight,
    bool? squareCutOut,
    double? cutOutBottomOffset,
    Color? borderColor,
    double? borderLength,
    double? borderWidth,
    double? borderRadius,
    Color? overlayColor,
    Color? scanLineColor,
    double? scanLineWidth,
    bool? showScanLine,
    Duration? scanLineDuration,
  }) {
    return ScannerOverlayStyle(
      cutOutWidthFactor: cutOutWidthFactor ?? this.cutOutWidthFactor,
      cutOutHeight: cutOutHeight ?? this.cutOutHeight,
      squareCutOut: squareCutOut ?? this.squareCutOut,
      cutOutBottomOffset: cutOutBottomOffset ?? this.cutOutBottomOffset,
      borderColor: borderColor ?? this.borderColor,
      borderLength: borderLength ?? this.borderLength,
      borderWidth: borderWidth ?? this.borderWidth,
      borderRadius: borderRadius ?? this.borderRadius,
      overlayColor: overlayColor ?? this.overlayColor,
      scanLineColor: scanLineColor ?? this.scanLineColor,
      scanLineWidth: scanLineWidth ?? this.scanLineWidth,
      showScanLine: showScanLine ?? this.showScanLine,
      scanLineDuration: scanLineDuration ?? this.scanLineDuration,
    );
  }

  // The overlay rebuilds its shape from this, and ShapeDecoration compares
  // shapes to decide whether the dimmed area has to be repainted. Without this
  // a style rebuilt inside a build method repaints the whole overlay on every
  // frame anything above it changes.
  @override
  bool operator ==(Object other) =>
      other is ScannerOverlayStyle &&
      other.cutOutWidthFactor == cutOutWidthFactor &&
      other.cutOutHeight == cutOutHeight &&
      other.squareCutOut == squareCutOut &&
      other.cutOutBottomOffset == cutOutBottomOffset &&
      other.borderColor == borderColor &&
      other.borderLength == borderLength &&
      other.borderWidth == borderWidth &&
      other.borderRadius == borderRadius &&
      other.overlayColor == overlayColor &&
      other.scanLineColor == scanLineColor &&
      other.scanLineWidth == scanLineWidth &&
      other.showScanLine == showScanLine &&
      other.scanLineDuration == scanLineDuration;

  @override
  int get hashCode => Object.hash(
        cutOutWidthFactor,
        cutOutHeight,
        squareCutOut,
        cutOutBottomOffset,
        borderColor,
        borderLength,
        borderWidth,
        borderRadius,
        overlayColor,
        scanLineColor,
        scanLineWidth,
        showScanLine,
        scanLineDuration,
      );
}
