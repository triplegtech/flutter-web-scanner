/// Symbologies the package can report.
///
/// Each value carries the wire names used by both decoding engines so that
/// mapping stays in one place: ZXing-JS reports SCREAMING_SNAKE names from its
/// `BarcodeFormat` enum, while the native `BarcodeDetector` API reports
/// lower_snake names. [unknown] is the fallback for anything unrecognised, so
/// a new engine format never crashes the mapping.
enum BarcodeFormat {
  aztec(zxing: 'AZTEC', native: 'aztec'),
  codabar(zxing: 'CODABAR', native: 'codabar'),
  code39(zxing: 'CODE_39', native: 'code_39'),
  code93(zxing: 'CODE_93', native: 'code_93'),
  code128(zxing: 'CODE_128', native: 'code_128'),
  dataMatrix(zxing: 'DATA_MATRIX', native: 'data_matrix'),
  ean8(zxing: 'EAN_8', native: 'ean_8'),
  ean13(zxing: 'EAN_13', native: 'ean_13'),
  itf(zxing: 'ITF', native: 'itf'),
  maxiCode(zxing: 'MAXICODE', native: null),
  pdf417(zxing: 'PDF_417', native: 'pdf417'),
  qrCode(zxing: 'QR_CODE', native: 'qr_code'),
  rss14(zxing: 'RSS_14', native: null),
  rssExpanded(zxing: 'RSS_EXPANDED', native: null),
  upcA(zxing: 'UPC_A', native: 'upc_a'),
  upcE(zxing: 'UPC_E', native: 'upc_e'),
  upcEanExtension(zxing: 'UPC_EAN_EXTENSION', native: null),
  unknown(zxing: null, native: 'unknown');

  const BarcodeFormat({required this.zxing, required this.native});

  /// Name reported by `@zxing/library`, or `null` if the format has no
  /// ZXing equivalent.
  final String? zxing;

  /// Name used by the native `BarcodeDetector` API, or `null` if unsupported
  /// there.
  final String? native;

  /// Every format that can actually be decoded, i.e. everything but [unknown].
  static Set<BarcodeFormat> get decodable =>
      values.where((f) => f != BarcodeFormat.unknown).toSet();

  /// Formats carrying a check digit that [BarcodeValidator] can verify.
  static const Set<BarcodeFormat> checksummed = {
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.itf,
  };

  /// Resolves an engine-reported name back to a [BarcodeFormat].
  ///
  /// Matching is case-insensitive and tolerant of both wire spellings, because
  /// engines are inconsistent about casing and about `CODE_39` vs `code_39`.
  /// Anything unrecognised maps to [unknown] rather than throwing — a scan that
  /// produced a value is still useful even if we cannot name its symbology.
  static BarcodeFormat parse(String? raw) {
    if (raw == null) return BarcodeFormat.unknown;
    final normalized = raw.trim().toLowerCase().replaceAll('-', '_');
    if (normalized.isEmpty) return BarcodeFormat.unknown;
    for (final format in values) {
      if (format.zxing?.toLowerCase() == normalized ||
          format.native?.toLowerCase() == normalized) {
        return format;
      }
    }
    return BarcodeFormat.unknown;
  }

  /// Whether a check digit can be verified for this format.
  bool get hasChecksum => checksummed.contains(this);
}
