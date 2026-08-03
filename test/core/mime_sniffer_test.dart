import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_qrcode_barcode_web_reader/src/core/mime_sniffer.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

Uint8List ascii(String text, {List<int> prefix = const <int>[]}) =>
    Uint8List.fromList([...prefix, ...text.codeUnits]);

void main() {
  group('sniff', () {
    test('detects PNG', () {
      expect(
        MimeSniffer.sniff(
          bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]),
        ),
        'image/png',
      );
    });

    test('detects JPEG', () {
      expect(
        MimeSniffer.sniff(bytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00])),
        'image/jpeg',
      );
    });

    test('detects GIF in both revisions', () {
      expect(MimeSniffer.sniff(ascii('GIF87a....')), 'image/gif');
      expect(MimeSniffer.sniff(ascii('GIF89a....')), 'image/gif');
    });

    test('detects BMP', () {
      expect(MimeSniffer.sniff(bytes([0x42, 0x4D, 0x00, 0x00])), 'image/bmp');
    });

    test('detects WEBP by its RIFF container tag at offset 8', () {
      final webp = Uint8List.fromList([
        ...'RIFF'.codeUnits,
        0x00, 0x00, 0x00, 0x00, // chunk size
        ...'WEBP'.codeUnits,
      ]);
      expect(MimeSniffer.sniff(webp), 'image/webp');
    });

    test('does not mistake a non-WEBP RIFF container for an image', () {
      final wav = Uint8List.fromList([
        ...'RIFF'.codeUnits,
        0x00,
        0x00,
        0x00,
        0x00,
        ...'WAVE'.codeUnits,
      ]);
      expect(MimeSniffer.sniff(wav), isNull);
    });

    test('detects TIFF in both byte orders', () {
      expect(
        MimeSniffer.sniff(bytes([0x49, 0x49, 0x2A, 0x00])),
        'image/tiff',
      );
      expect(
        MimeSniffer.sniff(bytes([0x4D, 0x4D, 0x00, 0x2A])),
        'image/tiff',
      );
    });

    test('detects HEIC by its ISO-BMFF brand', () {
      final heic = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18, // box size
        ...'ftyp'.codeUnits,
        ...'heic'.codeUnits,
      ]);
      expect(MimeSniffer.sniff(heic), 'image/heic');
    });

    test('rejects an ISO-BMFF file whose brand is not HEIF', () {
      final mp4 = Uint8List.fromList([
        0x00,
        0x00,
        0x00,
        0x18,
        ...'ftyp'.codeUnits,
        ...'isom'.codeUnits,
      ]);
      expect(MimeSniffer.sniff(mp4), isNull);
    });

    test('detects PDF', () {
      expect(MimeSniffer.sniff(ascii('%PDF-1.7')), 'application/pdf');
    });

    test('returns null for unrecognised bytes', () {
      expect(MimeSniffer.sniff(bytes([0x01, 0x02, 0x03, 0x04])), isNull);
    });

    test('returns null for an empty list without throwing', () {
      expect(MimeSniffer.sniff(bytes(const [])), isNull);
    });

    test('returns null for truncated input shorter than any signature', () {
      expect(MimeSniffer.sniff(bytes([0xFF])), isNull);
    });
  });

  group('isDecodableImage', () {
    test('accepts image formats the engines can read', () {
      expect(MimeSniffer.isDecodableImage(ascii('GIF89a')), isTrue);
    });

    test('rejects PDF, which sniffs successfully but cannot be decoded', () {
      expect(MimeSniffer.isDecodableImage(ascii('%PDF-1.7')), isFalse);
    });

    test('rejects unrecognised bytes', () {
      expect(MimeSniffer.isDecodableImage(bytes([0x00, 0x01])), isFalse);
    });
  });

  group('extensionFor', () {
    test('maps known types', () {
      expect(MimeSniffer.extensionFor('image/jpeg'), 'jpg');
      expect(MimeSniffer.extensionFor('image/png'), 'png');
    });

    test('falls back to bin for unknown types', () {
      expect(MimeSniffer.extensionFor('application/octet-stream'), 'bin');
    });
  });
}
