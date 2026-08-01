import 'package:omni_qrcode_barcode_web_reader/src/enums/barcode_format.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/scan_validation.dart';

/// Why a decoded payload was rejected.
enum BarcodeRejection {
  /// Payload was empty or whitespace only.
  empty,

  /// Shorter than [ScanValidation.minLength].
  tooShort,

  /// Symbology excluded by [ScanValidation.allowedFormats].
  formatNotAllowed,

  /// Characters that cannot occur in this symbology, e.g. letters in an EAN.
  invalidCharacters,

  /// Digit count does not match the symbology, e.g. a 12-digit EAN-13.
  invalidLength,

  /// Check digit did not match the payload.
  checksumMismatch,

  /// Rejected by the caller's [ScanValidation.guard].
  rejectedByGuard,
}

/// Result of validating a decoded payload.
sealed class ValidationOutcome {
  const ValidationOutcome();

  bool get isAccepted => this is ValidationAccepted;
}

/// The payload passed every enabled check.
final class ValidationAccepted extends ValidationOutcome {
  const ValidationAccepted({required this.checksumVerified});

  /// Whether a check digit was actually verified, as opposed to the format
  /// simply not carrying one.
  final bool checksumVerified;
}

/// The payload failed a check and must not be surfaced.
final class ValidationRejected extends ValidationOutcome {
  const ValidationRejected(this.reason, this.message);

  final BarcodeRejection reason;

  /// Human-readable detail, useful in logs when tuning validation.
  final String message;

  @override
  String toString() => 'ValidationRejected(${reason.name}: $message)';
}

/// Verifies decoded payloads against symbology rules and caller policy.
///
/// Every method is pure and side-effect free, so the entire validation surface
/// is unit-testable without a browser.
abstract final class BarcodeValidator {
  /// Digit counts that each symbology accepts. Formats absent from this map
  /// have no fixed length.
  static const Map<BarcodeFormat, Set<int>> _fixedLengths = {
    BarcodeFormat.ean13: {13},
    BarcodeFormat.ean8: {8},
    BarcodeFormat.upcA: {12},
    BarcodeFormat.upcE: {6, 7, 8},
  };

  /// Symbologies whose payload must be entirely numeric.
  static const Set<BarcodeFormat> _numericOnly = {
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.itf,
  };

  /// The Code 39 alphabet, excluding the `*` start/stop sentinel which
  /// decoders strip.
  static const String _code39Alphabet =
      r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%';

  /// Runs every check enabled by [validation] against [value].
  static ValidationOutcome validate(
    String value,
    BarcodeFormat format,
    ScanValidation validation,
  ) {
    if (value.trim().isEmpty) {
      return const ValidationRejected(
        BarcodeRejection.empty,
        'payload is empty',
      );
    }

    if (value.length < validation.minLength) {
      return ValidationRejected(
        BarcodeRejection.tooShort,
        'length ${value.length} is below minimum ${validation.minLength}',
      );
    }

    if (!validation.allowsFormat(format)) {
      return ValidationRejected(
        BarcodeRejection.formatNotAllowed,
        '${format.name} is not in the allowed format set',
      );
    }

    final structural = _validateStructure(value, format);
    if (structural != null) return structural;

    var checksumVerified = false;
    if (validation.requireChecksum && format.hasChecksum) {
      if (!hasValidChecksum(value, format)) {
        return ValidationRejected(
          BarcodeRejection.checksumMismatch,
          'check digit does not match payload $value',
        );
      }
      checksumVerified = true;
    }

    final guard = validation.guard;
    if (guard != null && !guard(value, format)) {
      return const ValidationRejected(
        BarcodeRejection.rejectedByGuard,
        'rejected by application guard',
      );
    }

    return ValidationAccepted(checksumVerified: checksumVerified);
  }

  /// Checks charset and length constraints implied by the symbology itself.
  ///
  /// Returns `null` when the payload is structurally sound.
  static ValidationRejected? _validateStructure(
    String value,
    BarcodeFormat format,
  ) {
    if (_numericOnly.contains(format) && !_isAllDigits(value)) {
      return ValidationRejected(
        BarcodeRejection.invalidCharacters,
        '${format.name} payloads must be numeric, got "$value"',
      );
    }

    if (format == BarcodeFormat.code39 && !_isCode39(value)) {
      return ValidationRejected(
        BarcodeRejection.invalidCharacters,
        'value contains characters outside the Code 39 alphabet',
      );
    }

    final allowedLengths = _fixedLengths[format];
    if (allowedLengths != null && !allowedLengths.contains(value.length)) {
      return ValidationRejected(
        BarcodeRejection.invalidLength,
        '${format.name} requires '
        '${allowedLengths.join(' or ')} digits, got ${value.length}',
      );
    }

    // ITF encodes digits in pairs, so an odd digit count means the decoder
    // dropped or invented one — a classic partial-read signature.
    if (format == BarcodeFormat.itf && value.length.isOdd) {
      return ValidationRejected(
        BarcodeRejection.invalidLength,
        'ITF payloads always have an even digit count, got ${value.length}',
      );
    }

    return null;
  }

  /// Verifies the check digit for symbologies that carry one.
  ///
  /// Returns `true` for formats without a checksum, since there is nothing to
  /// contradict. Callers that need to distinguish "verified" from "nothing to
  /// verify" should consult [BarcodeFormat.hasChecksum] first.
  static bool hasValidChecksum(String value, BarcodeFormat format) {
    return switch (format) {
      BarcodeFormat.ean13 ||
      BarcodeFormat.ean8 ||
      BarcodeFormat.upcA =>
        _hasValidGtinCheckDigit(value),
      BarcodeFormat.upcE => _hasValidUpcECheckDigit(value),
      // Only ITF-14 defines a check digit; other ITF lengths carry none.
      BarcodeFormat.itf =>
        value.length != 14 || _hasValidGtinCheckDigit(value),
      _ => true,
    };
  }

  /// Computes the modulo-10 check digit shared by every GTIN-family symbology
  /// (EAN-8, EAN-13, UPC-A, ITF-14).
  ///
  /// [payload] must exclude the check digit. Weights alternate 3 and 1 starting
  /// from the rightmost payload digit, which is what makes one implementation
  /// serve all four lengths.
  static int gtinCheckDigit(String payload) {
    var sum = 0;
    var weight = 3;
    for (var i = payload.length - 1; i >= 0; i--) {
      sum += _digitAt(payload, i) * weight;
      weight = weight == 3 ? 1 : 3;
    }
    return (10 - (sum % 10)) % 10;
  }

  static bool _hasValidGtinCheckDigit(String value) {
    if (value.length < 2 || !_isAllDigits(value)) return false;
    final payload = value.substring(0, value.length - 1);
    final expected = gtinCheckDigit(payload);
    return expected == _digitAt(value, value.length - 1);
  }

  /// Validates a UPC-E payload by expanding it to its UPC-A equivalent.
  ///
  /// UPC-E has no check digit of its own: the digit it carries is the check
  /// digit of the full UPC-A number it compresses, so the only correct way to
  /// verify it is to expand first.
  static bool _hasValidUpcECheckDigit(String value) {
    final expanded = expandUpcE(value);
    if (expanded == null) return false;
    return _hasValidGtinCheckDigit(expanded);
  }

  /// Expands a UPC-E payload into its 12-digit UPC-A form.
  ///
  /// Accepts the 6-digit bare form, the 7-digit form with a leading number
  /// system, and the 8-digit form with both number system and check digit.
  /// Returns `null` when the input cannot be a UPC-E.
  static String? expandUpcE(String value) {
    if (!_isAllDigits(value)) return null;

    final (numberSystem, body, checkDigit) = switch (value.length) {
      6 => ('0', value, null),
      7 => (value[0], value.substring(1), null),
      8 => (value[0], value.substring(1, 7), value[7]),
      _ => (null, '', null),
    };
    if (numberSystem == null) return null;
    // UPC-E only compresses number systems 0 and 1.
    if (numberSystem != '0' && numberSystem != '1') return null;

    final d = body;
    final manufacturerAndProduct = switch (d[5]) {
      '0' || '1' || '2' => '${d.substring(0, 2)}${d[5]}0000${d.substring(2, 5)}',
      '3' => '${d.substring(0, 3)}00000${d.substring(3, 5)}',
      '4' => '${d.substring(0, 4)}00000${d[4]}',
      _ => '${d.substring(0, 5)}0000${d[5]}',
    };

    final withoutCheck = '$numberSystem$manufacturerAndProduct';
    final check = checkDigit ?? gtinCheckDigit(withoutCheck).toString();
    return '$withoutCheck$check';
  }

  static bool _isAllDigits(String value) {
    if (value.isEmpty) return false;
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (code < 0x30 || code > 0x39) return false;
    }
    return true;
  }

  static bool _isCode39(String value) {
    for (var i = 0; i < value.length; i++) {
      if (!_code39Alphabet.contains(value[i])) return false;
    }
    return true;
  }

  static int _digitAt(String value, int index) => value.codeUnitAt(index) - 0x30;
}
