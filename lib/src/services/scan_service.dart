import 'dart:typed_data';

import 'package:flutter_web_scanner/src/core/barcode_validator.dart';
import 'package:flutter_web_scanner/src/core/mime_sniffer.dart';
import 'package:flutter_web_scanner/src/enums/scan_engine.dart';
import 'package:flutter_web_scanner/src/enums/scan_mode.dart';
import 'package:flutter_web_scanner/src/models/barcode_result.dart';
import 'package:flutter_web_scanner/src/models/scan_validation.dart';
import 'package:flutter_web_scanner/src/models/scanner_failure.dart';
import 'package:flutter_web_scanner/src/platform/scanner_platform.dart';

/// Decodes a barcode or QR code from raw image bytes.
///
/// Returns `null` when the image contains no readable code, or when what was
/// decoded failed validation. Throws [ScannerFailure] when the image itself
/// could not be processed — unrecognised bytes, or an unavailable engine.
///
/// ```dart
/// final bytes = await pickedFile.readAsBytes();
/// final result = await decodeBarcodeFromBytes(bytes, mode: ScanMode.barcode);
/// ```
///
/// Two fixes relative to 1.x: the symbology reported is the one the engine
/// actually found rather than a hardcoded `EAN-13`, and the same check-digit
/// verification the live scanner uses is applied here too.
Future<BarcodeResult?> decodeBarcodeFromBytes(
  Uint8List imageData, {
  ScanMode mode = ScanMode.all,
  ScanEngine engine = ScanEngine.zxing,
  ScanValidation? validation,
  ScannerPlatform? platform,
}) async {
  if (imageData.isEmpty) {
    throw const ScannerFailure(
      ScannerFailureKind.unknown,
      'cannot decode an empty byte list',
    );
  }

  // Sniffing beats trusting a filename: the browser refuses to decode a Blob
  // whose declared type disagrees with its content, and callers routinely hand
  // over bytes with no type information at all.
  final mimeType = MimeSniffer.sniff(imageData);
  if (mimeType == null) {
    throw const ScannerFailure(
      ScannerFailureKind.unknown,
      'the bytes do not match any recognised image format',
    );
  }
  if (!MimeSniffer.decodableImageTypes.contains(mimeType)) {
    throw ScannerFailure(
      ScannerFailureKind.unknown,
      '$mimeType is not an image format the decoding engines can read',
    );
  }

  final scanner = platform ?? ScannerPlatformResolver.instance;
  await scanner.initialize();

  final decode = await scanner.decodeImage(
    bytes: imageData,
    mimeType: mimeType,
    mode: mode,
    engine: engine,
  );
  if (decode == null) return null;

  // A still image gets exactly one attempt, so confirmation counting is
  // meaningless here; structural and checksum validation still apply.
  final rules = (validation ?? ScanValidation.forMode(mode)).copyWith(
    confirmations: 1,
  );
  final outcome = BarcodeValidator.validate(decode.value, decode.format, rules);

  return switch (outcome) {
    ValidationAccepted(:final checksumVerified) => BarcodeResult(
      value: decode.value,
      format: decode.format,
      rawFormat: decode.rawFormat,
      checksumVerified: checksumVerified,
    ),
    // A payload that fails its own check digit is a misread, not a result.
    ValidationRejected() => null,
  };
}
