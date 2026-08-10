import 'package:omni_qrcode_barcode_web_reader/src/core/barcode_validator.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/barcode_format.dart';

/// A decode the validation pipeline threw away before `onDetect`.
///
/// Rejections are routine — a live camera produces dozens per second while the
/// user is still aiming, and discarding them is the whole point of
/// [ScanValidation]. They only become interesting when *every* read is
/// rejected, which looks identical to a scanner that is simply not decoding:
/// the preview is live, no failure is raised, and nothing ever fires. This is
/// the one place that difference is observable, so it is what a caller reaches
/// for when a code that should scan does not.
class ScanRejection {
  const ScanRejection({
    required this.value,
    required this.format,
    required this.rawFormat,
    required this.reason,
    required this.message,
  });

  /// The decoded payload, exactly as the engine returned it.
  final String value;

  final BarcodeFormat format;

  /// Symbology name as the engine spelled it, before [BarcodeFormat.parse].
  ///
  /// Worth reading whenever [format] is [BarcodeFormat.unknown], because that
  /// value conflates two very different situations: an engine naming a
  /// symbology this package does not model, and an engine reporting a name
  /// nothing can parse. Only the raw string tells them apart.
  final String? rawFormat;

  final BarcodeRejection reason;

  /// Human-readable detail naming the actual threshold that was missed.
  final String message;

  @override
  String toString() => 'ScanRejection(${reason.name}: $message, '
      'value: $value, format: ${format.name}, rawFormat: $rawFormat)';
}
