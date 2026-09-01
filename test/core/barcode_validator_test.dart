import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_scanner/flutter_web_scanner.dart';

void main() {
  group('gtinCheckDigit', () {
    // Published GTIN examples; the payload excludes the trailing check digit.
    const cases = <String, int>{
      '590123412345': 7, // EAN-13
      '400638133393': 1, // EAN-13
      '978030640615': 7, // ISBN-13
      '9638507': 4, // EAN-8
      '03600029145': 2, // UPC-A
    };

    cases.forEach((payload, expected) {
      test('computes $expected for $payload', () {
        expect(BarcodeValidator.gtinCheckDigit(payload), expected);
      });
    });
  });

  group('hasValidChecksum', () {
    test('accepts a well-formed EAN-13', () {
      expect(
        BarcodeValidator.hasValidChecksum('5901234123457', BarcodeFormat.ean13),
        isTrue,
      );
    });

    test('rejects an EAN-13 whose check digit is off by one', () {
      expect(
        BarcodeValidator.hasValidChecksum('5901234123458', BarcodeFormat.ean13),
        isFalse,
      );
    });

    test('accepts a well-formed EAN-8', () {
      expect(
        BarcodeValidator.hasValidChecksum('96385074', BarcodeFormat.ean8),
        isTrue,
      );
    });

    test('accepts a well-formed UPC-A', () {
      expect(
        BarcodeValidator.hasValidChecksum('036000291452', BarcodeFormat.upcA),
        isTrue,
      );
    });

    test('accepts formats that carry no check digit', () {
      expect(
        BarcodeValidator.hasValidChecksum('anything', BarcodeFormat.qrCode),
        isTrue,
      );
      expect(
        BarcodeValidator.hasValidChecksum('ABC-123', BarcodeFormat.code128),
        isTrue,
      );
    });

    test('only checks ITF payloads of length 14, since shorter ITF has no '
        'check digit', () {
      // ITF-14 with a valid check digit.
      expect(
        BarcodeValidator.hasValidChecksum('00012345678905', BarcodeFormat.itf),
        isTrue,
      );
      // Six digits: no check digit is defined, so nothing can contradict it.
      expect(
        BarcodeValidator.hasValidChecksum('123456', BarcodeFormat.itf),
        isTrue,
      );
    });
  });

  group('expandUpcE', () {
    test('expands the D6 in 0-2 form', () {
      // 04252614 -> 042100005264 is the canonical worked example.
      expect(BarcodeValidator.expandUpcE('04252614'), '042100005264');
    });

    test('expands the D6 == 3 form by inserting five zeros after D3', () {
      final expanded = BarcodeValidator.expandUpcE('0456003');
      expect(expanded, startsWith('045600000'));
      expect(expanded, hasLength(12));
    });

    test('expands the D6 == 4 form by inserting five zeros after D4', () {
      final expanded = BarcodeValidator.expandUpcE('0456704');
      expect(expanded, startsWith('045670000'));
      expect(expanded, hasLength(12));
    });

    test('expands the D6 in 5-9 form by inserting four zeros after D5', () {
      final expanded = BarcodeValidator.expandUpcE('0456789');
      expect(expanded, startsWith('045678'));
      expect(expanded, hasLength(12));
    });

    test('expands the trailing-digit form and round-trips its check digit', () {
      final expanded = BarcodeValidator.expandUpcE('01234565');
      expect(expanded, '012345000065');
      expect(
        BarcodeValidator.hasValidChecksum(expanded!, BarcodeFormat.upcA),
        isTrue,
      );
    });

    test('returns null for non-numeric input', () {
      expect(BarcodeValidator.expandUpcE('0123A5'), isNull);
    });

    test('returns null for number systems other than 0 and 1', () {
      expect(BarcodeValidator.expandUpcE('42345650'), isNull);
    });
  });

  group('validate', () {
    const validation = ScanValidation();

    ValidationOutcome check(String value, BarcodeFormat format) =>
        BarcodeValidator.validate(value, format, validation);

    test('accepts a valid EAN-13 and reports the checksum as verified', () {
      final outcome = check('5901234123457', BarcodeFormat.ean13);
      expect(outcome, isA<ValidationAccepted>());
      expect((outcome as ValidationAccepted).checksumVerified, isTrue);
    });

    test('rejects an empty payload', () {
      final outcome = check('   ', BarcodeFormat.qrCode);
      expect(outcome, isA<ValidationRejected>());
      expect((outcome as ValidationRejected).reason, BarcodeRejection.empty);
    });

    test('rejects letters in a numeric-only symbology', () {
      final outcome = check('59012341234A', BarcodeFormat.ean13);
      expect(
        (outcome as ValidationRejected).reason,
        BarcodeRejection.invalidCharacters,
      );
    });

    test('rejects an EAN-13 with the wrong digit count', () {
      // A truncated read is the classic partial-decode failure mode.
      final outcome = check('590123412345', BarcodeFormat.ean13);
      expect(
        (outcome as ValidationRejected).reason,
        BarcodeRejection.invalidLength,
      );
    });

    test('rejects an ITF payload with an odd digit count', () {
      final outcome = check('12345', BarcodeFormat.itf);
      expect(
        (outcome as ValidationRejected).reason,
        BarcodeRejection.invalidLength,
      );
    });

    test('rejects a checksum mismatch', () {
      final outcome = check('5901234123458', BarcodeFormat.ean13);
      expect(
        (outcome as ValidationRejected).reason,
        BarcodeRejection.checksumMismatch,
      );
    });

    test('accepts a checksum mismatch when verification is disabled', () {
      final outcome = BarcodeValidator.validate(
        '5901234123458',
        BarcodeFormat.ean13,
        const ScanValidation(requireChecksum: false),
      );
      expect(outcome, isA<ValidationAccepted>());
      expect((outcome as ValidationAccepted).checksumVerified, isFalse);
    });

    test('rejects payloads below minLength', () {
      final outcome = BarcodeValidator.validate(
        'ab',
        BarcodeFormat.qrCode,
        const ScanValidation(minLength: 5),
      );
      expect((outcome as ValidationRejected).reason, BarcodeRejection.tooShort);
    });

    test('rejects formats outside allowedFormats', () {
      final outcome = BarcodeValidator.validate(
        '5901234123457',
        BarcodeFormat.ean13,
        const ScanValidation(allowedFormats: {BarcodeFormat.qrCode}),
      );
      expect(
        (outcome as ValidationRejected).reason,
        BarcodeRejection.formatNotAllowed,
      );
    });

    test('rejects values turned down by the caller guard', () {
      final outcome = BarcodeValidator.validate(
        '5901234123457',
        BarcodeFormat.ean13,
        ScanValidation(guard: (value, _) => value.startsWith('789')),
      );
      expect(
        (outcome as ValidationRejected).reason,
        BarcodeRejection.rejectedByGuard,
      );
    });

    test('rejects characters outside the Code 39 alphabet', () {
      final outcome = check('ABC#123', BarcodeFormat.code39);
      expect(
        (outcome as ValidationRejected).reason,
        BarcodeRejection.invalidCharacters,
      );
    });

    test('accepts the full Code 39 alphabet', () {
      expect(
        check(r'AB-12. $/+%', BarcodeFormat.code39),
        isA<ValidationAccepted>(),
      );
    });

    test('accepts arbitrary QR payloads including newlines', () {
      expect(
        check('https://example.com\nline two', BarcodeFormat.qrCode),
        isA<ValidationAccepted>(),
      );
    });
  });
}
