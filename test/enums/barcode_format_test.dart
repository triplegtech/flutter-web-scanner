import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_scanner/flutter_web_scanner.dart';

void main() {
  group('parse', () {
    test('reads ZXing SCREAMING_SNAKE names', () {
      expect(BarcodeFormat.parse('EAN_13'), BarcodeFormat.ean13);
      expect(BarcodeFormat.parse('QR_CODE'), BarcodeFormat.qrCode);
      expect(BarcodeFormat.parse('UPC_A'), BarcodeFormat.upcA);
    });

    test('reads native BarcodeDetector lower_snake names', () {
      expect(BarcodeFormat.parse('ean_13'), BarcodeFormat.ean13);
      expect(BarcodeFormat.parse('qr_code'), BarcodeFormat.qrCode);
      expect(BarcodeFormat.parse('pdf417'), BarcodeFormat.pdf417);
    });

    test('tolerates hyphens, casing and surrounding whitespace', () {
      expect(BarcodeFormat.parse('EAN-13'), BarcodeFormat.ean13);
      expect(BarcodeFormat.parse('  Ean_13 '), BarcodeFormat.ean13);
    });

    test('degrades to unknown rather than throwing', () {
      // A new engine format must never crash the mapping: a scan that produced
      // a value is still useful even when we cannot name its symbology.
      expect(BarcodeFormat.parse('SOME_NEW_FORMAT'), BarcodeFormat.unknown);
      expect(BarcodeFormat.parse(null), BarcodeFormat.unknown);
      expect(BarcodeFormat.parse(''), BarcodeFormat.unknown);
      expect(BarcodeFormat.parse('   '), BarcodeFormat.unknown);
    });
  });

  group('hasChecksum', () {
    test('is true for the GTIN family', () {
      expect(BarcodeFormat.ean13.hasChecksum, isTrue);
      expect(BarcodeFormat.ean8.hasChecksum, isTrue);
      expect(BarcodeFormat.upcA.hasChecksum, isTrue);
      expect(BarcodeFormat.upcE.hasChecksum, isTrue);
      expect(BarcodeFormat.itf.hasChecksum, isTrue);
    });

    test('is false for symbologies with no external check digit', () {
      expect(BarcodeFormat.qrCode.hasChecksum, isFalse);
      expect(BarcodeFormat.code128.hasChecksum, isFalse);
      expect(BarcodeFormat.dataMatrix.hasChecksum, isFalse);
    });
  });

  group('decodable', () {
    test('excludes the unknown sentinel', () {
      expect(BarcodeFormat.decodable, isNot(contains(BarcodeFormat.unknown)));
      expect(BarcodeFormat.decodable, contains(BarcodeFormat.ean13));
    });
  });

  group('ScanMode.formats', () {
    test('restricts qrCode mode to 2D symbologies', () {
      expect(ScanMode.qrCode.formats, contains(BarcodeFormat.qrCode));
      expect(ScanMode.qrCode.formats, isNot(contains(BarcodeFormat.ean13)));
    });

    test('restricts barcode mode to 1D symbologies', () {
      expect(ScanMode.barcode.formats, contains(BarcodeFormat.ean13));
      expect(ScanMode.barcode.formats, isNot(contains(BarcodeFormat.qrCode)));
    });

    test('marks only barcode mode as linear', () {
      expect(ScanMode.barcode.isLinear, isTrue);
      expect(ScanMode.qrCode.isLinear, isFalse);
      expect(ScanMode.all.isLinear, isFalse);
    });
  });
}
