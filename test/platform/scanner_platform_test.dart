import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_qrcode_barcode_web_reader/omni_qrcode_barcode_web_reader.dart';
import 'package:omni_qrcode_barcode_web_reader/src/platform/scanner_platform_stub.dart';

import '../fakes/fake_scanner_platform.dart';

void main() {
  Matcher throwsUnsupported() => throwsA(
        isA<ScannerFailure>().having(
          (failure) => failure.kind,
          'kind',
          ScannerFailureKind.unsupportedPlatform,
        ),
      );

  group('EngineAvailability.resolve', () {
    const both = EngineAvailability(
      zxingLoaded: true,
      nativeSupported: true,
      secureContext: true,
    );
    const zxingOnly = EngineAvailability(
      zxingLoaded: true,
      nativeSupported: false,
      secureContext: true,
    );
    const nativeOnly = EngineAvailability(
      zxingLoaded: false,
      nativeSupported: true,
      secureContext: true,
    );
    const neither = EngineAvailability(
      zxingLoaded: false,
      nativeSupported: false,
      secureContext: true,
    );

    test('auto prefers the browser detector when it exists', () {
      expect(both.resolve(ScanEngine.auto), ScanEngine.native);
      expect(nativeOnly.resolve(ScanEngine.auto), ScanEngine.native);
    });

    test('auto falls back to ZXing where BarcodeDetector is missing', () {
      expect(zxingOnly.resolve(ScanEngine.auto), ScanEngine.zxing);
    });

    test('an explicit choice is honoured when it is available', () {
      expect(both.resolve(ScanEngine.zxing), ScanEngine.zxing);
      expect(both.resolve(ScanEngine.native), ScanEngine.native);
    });

    test('an explicit choice fails loudly rather than silently substituting',
        () {
      // Silently swapping engines would change which symbologies decode and
      // how fast, with no way for the caller to find out.
      expect(
        () => zxingOnly.resolve(ScanEngine.native),
        throwsA(isA<ScannerFailure>().having(
          (failure) => failure.kind,
          'kind',
          ScannerFailureKind.engineUnavailable,
        )),
      );
      expect(
        () => nativeOnly.resolve(ScanEngine.zxing),
        throwsA(isA<ScannerFailure>()),
      );
    });

    test('auto fails when the page loaded no engine at all', () {
      expect(
        () => neither.resolve(ScanEngine.auto),
        throwsA(isA<ScannerFailure>().having(
          (failure) => failure.message,
          'message',
          contains('index.html'),
        )),
      );
    });
  });

  group('UnsupportedScannerPlatform', () {
    const platform = UnsupportedScannerPlatform();

    test('refuses every operation that would need a camera', () {
      expect(platform.initialize, throwsUnsupported());
      expect(platform.listCameras, throwsUnsupported());
      expect(
        () => platform.decodeImage(
          bytes: Uint8List.fromList([0x00]),
          mimeType: 'image/png',
          mode: ScanMode.all,
          engine: ScanEngine.zxing,
        ),
        throwsUnsupported(),
      );
    });

    test('teardown and probing stay silent, so cleanup paths do not crash',
        () async {
      // dispose() calls stopSession without awaiting it; throwing there would
      // surface as an unhandled async error on every non-web teardown.
      await expectLater(platform.stopSession('any'), completes);
      expect(await platform.probeCamera('any'), isNull);
      expect(
        () => platform.registerView(viewId: 'v', containerId: 'c'),
        returnsNormally,
      );
    });
  });

  group('ScannerPlatformResolver', () {
    tearDown(ScannerPlatformResolver.reset);

    test('hands out the unsupported implementation off the web', () {
      expect(
        ScannerPlatformResolver.instance,
        isA<UnsupportedScannerPlatform>(),
      );
    });

    test('an override takes effect and can be undone', () {
      final fake = FakeScannerPlatform();
      ScannerPlatformResolver.instance = fake;
      expect(ScannerPlatformResolver.instance, same(fake));

      ScannerPlatformResolver.reset();
      expect(
        ScannerPlatformResolver.instance,
        isA<UnsupportedScannerPlatform>(),
      );
    });
  });

  group('RawDecode', () {
    test('maps the engine format string to a known symbology', () {
      expect(
        const RawDecode(value: 'x', rawFormat: 'EAN_13').format,
        BarcodeFormat.ean13,
      );
    });

    test('degrades to unknown while keeping the original string', () {
      // A symbology this package does not model still has to reach the caller
      // intact, so they can decide what to do with it.
      const decode = RawDecode(value: 'x', rawFormat: 'DX_FILM_EDGE');

      expect(decode.format, BarcodeFormat.unknown);
      expect(decode.rawFormat, 'DX_FILM_EDGE');
    });
  });
}
