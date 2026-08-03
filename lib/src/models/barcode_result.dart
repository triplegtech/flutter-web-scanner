import 'package:omni_qrcode_barcode_web_reader/src/enums/barcode_format.dart';

/// A successfully decoded and validated code.
class BarcodeResult {
  const BarcodeResult({
    required this.value,
    required this.format,
    this.rawFormat,
    this.confirmations = 1,
    this.checksumVerified = false,
  });

  /// Decoded payload text.
  final String value;

  /// Symbology the engine reported, mapped to a known value.
  ///
  /// May be [BarcodeFormat.unknown] when the engine reported a symbology this
  /// package does not model; [rawFormat] still carries the original string.
  final BarcodeFormat format;

  /// Untouched format string from the engine, kept for diagnostics.
  final String? rawFormat;

  /// How many consecutive identical reads backed this result.
  ///
  /// Always `>= 1`. Values above 1 mean the stabiliser confirmed the read
  /// across multiple frames, which is the main defence against partial 1D
  /// decodes.
  final int confirmations;

  /// Whether a check digit was verified for this value.
  ///
  /// `false` either because the format carries no checksum or because
  /// verification was disabled.
  final bool checksumVerified;

  BarcodeResult copyWith({
    String? value,
    BarcodeFormat? format,
    String? rawFormat,
    int? confirmations,
    bool? checksumVerified,
  }) {
    return BarcodeResult(
      value: value ?? this.value,
      format: format ?? this.format,
      rawFormat: rawFormat ?? this.rawFormat,
      confirmations: confirmations ?? this.confirmations,
      checksumVerified: checksumVerified ?? this.checksumVerified,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BarcodeResult && other.value == value && other.format == format;

  @override
  int get hashCode => Object.hash(value, format);

  @override
  String toString() => 'BarcodeResult(value: $value, format: ${format.name}, '
      'confirmations: $confirmations, checksumVerified: $checksumVerified)';
}
