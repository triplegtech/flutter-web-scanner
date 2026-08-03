import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_qrcode_barcode_web_reader/omni_qrcode_barcode_web_reader.dart';

import '../fakes/fake_scanner_platform.dart';

void main() {
  late FakeScannerPlatform platform;

  setUp(() => platform = FakeScannerPlatform());

  /// Minimal byte sequences carrying only the magic number each format is
  /// recognised by — the fake never actually decodes them.
  final png = Uint8List.fromList(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01],
  );
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00]);
  final pdf = Uint8List.fromList('%PDF-1.7'.codeUnits);

  // A valid EAN-13 and one whose check digit is wrong.
  const validEan = '5901234123457';
  const brokenEan = '5901234123456';

  Future<BarcodeResult?> decode(
    Uint8List bytes, {
    ScanMode mode = ScanMode.all,
    ScanEngine engine = ScanEngine.zxing,
    ScanValidation? validation,
  }) {
    return decodeBarcodeFromBytes(
      bytes,
      mode: mode,
      engine: engine,
      validation: validation,
      platform: platform,
    );
  }

  group('input handling', () {
    test('rejects an empty byte list', () {
      expect(
        () => decode(Uint8List(0)),
        throwsA(isA<ScannerFailure>()),
      );
    });

    test('rejects bytes that match no known image format', () {
      expect(
        () => decode(Uint8List.fromList([0x00, 0x01, 0x02, 0x03])),
        throwsA(isA<ScannerFailure>()),
      );
    });

    test('rejects a recognised format the engines cannot read', () async {
      // A PDF sniffs cleanly but no decoding engine accepts one, so this must
      // fail loudly rather than come back as "no code found".
      await expectLater(
        decode(pdf),
        throwsA(
          isA<ScannerFailure>().having(
            (failure) => failure.message,
            'message',
            contains('application/pdf'),
          ),
        ),
      );
      expect(platform.decodeRequests, isEmpty);
    });

    test('sniffs the MIME type instead of trusting the caller', () async {
      platform.imageDecode = const RawDecode(value: validEan);

      await decode(jpeg);

      expect(platform.decodeRequests.single.mimeType, 'image/jpeg');
    });

    test('initialises the platform before decoding', () async {
      platform.imageDecode = const RawDecode(value: validEan);

      await decode(png);

      expect(platform.initializeCount, 1);
    });

    test('forwards the requested mode and engine', () async {
      platform.imageDecode = const RawDecode(value: validEan);

      await decode(png, mode: ScanMode.qrCode, engine: ScanEngine.auto);

      expect(platform.decodeRequests.single.mode, ScanMode.qrCode);
      expect(platform.decodeRequests.single.engine, ScanEngine.auto);
    });
  });

  group('results', () {
    test('returns null when the image holds no readable code', () async {
      platform.imageDecode = null;

      expect(await decode(png), isNull);
    });

    test('reports the symbology the engine actually found', () async {
      platform.imageDecode = const RawDecode(
        value: 'https://example.com',
        rawFormat: 'QR_CODE',
      );

      final result = await decode(png);

      // 1.x hardcoded EAN-13 here regardless of what was in the image.
      expect(result?.format, BarcodeFormat.qrCode);
      expect(result?.rawFormat, 'QR_CODE');
    });

    test('verifies the check digit on a linear symbology', () async {
      platform.imageDecode = const RawDecode(
        value: validEan,
        rawFormat: 'EAN_13',
      );

      final result = await decode(png);

      expect(result?.value, validEan);
      expect(result?.checksumVerified, isTrue);
    });

    test('returns null for a payload that fails its own check digit', () async {
      platform.imageDecode = const RawDecode(
        value: brokenEan,
        rawFormat: 'EAN_13',
      );

      // A wrong check digit means a misread, and a misread is not a result.
      expect(await decode(png), isNull);
    });

    test('decodes a single frame even under a multi-confirmation preset',
        () async {
      platform.imageDecode = const RawDecode(
        value: validEan,
        rawFormat: 'EAN_13',
      );

      // A still image gets exactly one attempt, so confirmation counting would
      // reject every image it is applied to.
      final result = await decode(png, validation: ScanValidation.strict);

      expect(result?.value, validEan);
    });

    test('honours a caller-supplied guard', () async {
      platform.imageDecode = const RawDecode(
        value: validEan,
        rawFormat: 'EAN_13',
      );

      final result = await decode(
        png,
        validation: ScanValidation(guard: (value, _) => value.startsWith('99')),
      );

      expect(result, isNull);
    });

    test('rejects a format outside the allowed set', () async {
      platform.imageDecode = const RawDecode(
        value: 'https://example.com',
        rawFormat: 'QR_CODE',
      );

      final result = await decode(
        png,
        validation: const ScanValidation(
          allowedFormats: {BarcodeFormat.ean13},
        ),
      );

      expect(result, isNull);
    });

    test('surfaces a platform decode failure to the caller', () async {
      platform.decodeImageError = const ScannerFailure(
        ScannerFailureKind.engineUnavailable,
        'ZXing missing',
      );

      await expectLater(
        decode(png),
        throwsA(
          isA<ScannerFailure>().having(
            (failure) => failure.kind,
            'kind',
            ScannerFailureKind.engineUnavailable,
          ),
        ),
      );
    });
  });
}
