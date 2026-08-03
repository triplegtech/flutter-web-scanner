import 'package:flutter/widgets.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_mode.dart';

/// Appearance of the framing overlay drawn over the camera preview.
///
/// 1.x shipped two near-identical overlay widgets that differed only in four
/// hardcoded numbers and could not be customised at all. One parameterised
/// style replaces both.
class ScannerOverlayStyle {
  const ScannerOverlayStyle({
    this.cutOutWidthFactor = 0.85,
    this.cutOutHeight = 330,
    this.cutOutBottomOffset = 20,
    this.borderColor = const Color(0xFFFFFFFF),
    this.borderLength = 30,
    this.borderWidth = 8,
    this.borderRadius = 10,
    this.overlayColor = const Color(0xBF000000),
    this.scanLineColor = const Color(0xFFE53935),
    this.scanLineWidth = 3,
    this.showScanLine = true,
    this.scanLineDuration = const Duration(seconds: 2),
  })  : assert(
          cutOutWidthFactor > 0 && cutOutWidthFactor <= 1,
          'cutOutWidthFactor must be within (0, 1]',
        ),
        assert(cutOutHeight > 0, 'cutOutHeight must be positive');

  /// Cut-out width as a fraction of the available width.
  final double cutOutWidthFactor;

  /// Cut-out height in logical pixels.
  final double cutOutHeight;

  /// Shifts the cut-out up from centre, leaving room for instructions below.
  final double cutOutBottomOffset;

  final Color borderColor;

  /// Length of each corner bracket.
  final double borderLength;

  final double borderWidth;
  final double borderRadius;

  /// Colour of the dimmed area outside the cut-out.
  final Color overlayColor;

  final Color scanLineColor;
  final double scanLineWidth;

  /// Whether to animate a sweeping line inside the cut-out.
  final bool showScanLine;

  /// One full sweep of the scan line.
  final Duration scanLineDuration;

  /// Defaults shaped for [mode].
  ///
  /// A 1D barcode wants a wide, short window that discourages holding the
  /// phone too close; a QR code wants a near-square one.
  factory ScannerOverlayStyle.forMode(ScanMode mode) => mode.isLinear
      ? const ScannerOverlayStyle(
          cutOutWidthFactor: 0.7,
          cutOutHeight: 150,
          borderLength: 25,
          borderRadius: 8,
        )
      : const ScannerOverlayStyle();

  ScannerOverlayStyle copyWith({
    double? cutOutWidthFactor,
    double? cutOutHeight,
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
}
