import 'package:omni_qrcode_barcode_web_reader/src/enums/barcode_format.dart';

/// What the scanner should look for.
///
/// This drives two things at once: which overlay is drawn, and which formats
/// are handed to the decoding engine as a hint. Restricting the format set is
/// the single cheapest way to speed up decoding and cut false positives, so
/// prefer the narrowest mode that fits the use case.
enum ScanMode {
  /// 2D codes only (QR / Data Matrix / Aztec / PDF417).
  qrCode,

  /// 1D retail and logistics barcodes.
  barcode,

  /// Every format the engine supports. Slowest and most false-positive prone;
  /// use only when the input is genuinely unknown.
  all;

  /// Formats passed to the decoder as a hint for this mode.
  Set<BarcodeFormat> get formats => switch (this) {
        ScanMode.qrCode => const {
            BarcodeFormat.qrCode,
            BarcodeFormat.dataMatrix,
            BarcodeFormat.aztec,
            BarcodeFormat.pdf417,
          },
        ScanMode.barcode => const {
            BarcodeFormat.ean13,
            BarcodeFormat.ean8,
            BarcodeFormat.upcA,
            BarcodeFormat.upcE,
            BarcodeFormat.code128,
            BarcodeFormat.code39,
            BarcodeFormat.code93,
            BarcodeFormat.itf,
            BarcodeFormat.codabar,
          },
        ScanMode.all => BarcodeFormat.decodable,
      };

  /// Whether this mode is dominated by 1D symbologies.
  ///
  /// 1D codes are far more sensitive to horizontal resolution and to lens
  /// distortion than 2D codes, which changes both the camera we pick and the
  /// resolution we request.
  bool get isLinear => this == ScanMode.barcode;
}
