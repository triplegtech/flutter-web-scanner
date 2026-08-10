import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_qrcode_barcode_web_reader/omni_qrcode_barcode_web_reader.dart';

void main() {
  group('CameraPreferences', () {
    test('asks for a close-focusing lens only for linear symbologies', () {
      // A 1D barcode is presented close and needs horizontal resolution; a QR
      // code is read at arm's length, where the ultra-wide's distortion costs
      // more than its close focus gains.
      expect(
        CameraPreferences.forMode(ScanMode.barcode).distance,
        ScanDistance.near,
      );
      expect(
        CameraPreferences.forMode(ScanMode.qrCode).distance,
        ScanDistance.auto,
      );
    });

    test('spares the 1D reader its per-row blow-up in barcode mode', () {
      // TRY_HARDER makes ZXing's OneDReader scan every row of the region
      // instead of 15 across its middle, then repeat on a rotated copy, once
      // per enabled symbology. Ten times a second on the thread that renders
      // the page, that is what made the preview stutter in barcode mode.
      final barcode = CameraPreferences.forMode(ScanMode.barcode);

      expect(barcode.tryHarder, isFalse);
      // A linear symbol is a band, so most of the frame's height is waste.
      expect(barcode.roiHeightFactor, lessThan(1.0));
      // Its width is not: a barcode can be wider than the framing window.
      expect(barcode.roiWidthFactor, 1.0);
    });

    test('leaves the 2D detector working hard', () {
      // QR decoding is a single-pass detector with no per-row loop to blow up,
      // so the accuracy is worth having.
      final qr = CameraPreferences.forMode(ScanMode.qrCode);

      expect(qr.tryHarder, isTrue);
      expect(qr.roiHeightFactor, 1.0);
    });

    test('requests a resolution high enough to resolve bar widths', () {
      // Browsers hand back 640x480 unless asked otherwise, at which an EAN-13
      // held at arm's length lands on too few pixels to decode.
      const preferences = CameraPreferences();

      expect(preferences.idealWidth, greaterThanOrEqualTo(1280));
      expect(preferences.idealHeight, greaterThanOrEqualTo(720));
    });

    test('probes by default, but with a cap on how many cameras', () {
      const preferences = CameraPreferences();

      expect(preferences.probeCapabilities, isTrue);
      expect(preferences.maxProbedCameras, greaterThan(0));
    });

    test('leaves the main thread idle between decode attempts', () {
      // Decoding runs on the thread that renders the page, so a zero gap —
      // which is what ZXing does when left alone — starves Flutter entirely.
      const preferences = CameraPreferences();

      expect(preferences.decodeInterval, greaterThan(Duration.zero));
      // Still comfortably more attempts per second than the two confirmations
      // a barcode read needs inside its 1500 ms window.
      expect(
        preferences.decodeInterval,
        lessThanOrEqualTo(const Duration(milliseconds: 200)),
      );
    });

    test('decodes the whole visible frame until told otherwise', () {
      // The region is measured against what the preview shows, not the sensor
      // frame, so 1.0 already discards everything cropped away by object-fit.
      const preferences = CameraPreferences();

      expect(preferences.roiWidthFactor, 1.0);
      expect(preferences.roiHeightFactor, 1.0);
      expect(preferences.tryHarder, isTrue);
    });

    test('copyWith replaces only what it is given', () {
      const preferences = CameraPreferences(distance: ScanDistance.near);
      final zoomed = preferences.copyWith(zoom: 2, torch: true);

      expect(zoomed.zoom, 2);
      expect(zoomed.torch, isTrue);
      expect(zoomed.distance, ScanDistance.near);
      expect(zoomed.idealWidth, preferences.idealWidth);
    });

    test('copyWith carries the decode tuning across', () {
      const preferences = CameraPreferences();
      final tuned = preferences.copyWith(
        decodeInterval: const Duration(milliseconds: 250),
        roiHeightFactor: 0.5,
        tryHarder: false,
      );

      expect(tuned.decodeInterval, const Duration(milliseconds: 250));
      expect(tuned.roiHeightFactor, 0.5);
      expect(tuned.tryHarder, isFalse);
      expect(tuned.roiWidthFactor, preferences.roiWidthFactor);
    });

    test('rejects settings that cannot describe a camera', () {
      expect(() => CameraPreferences(idealWidth: 0), throwsAssertionError);
      expect(
          () => CameraPreferences(maxProbedCameras: -1), throwsAssertionError);
      // Below 1.0 is not zoom, it is a wider field of view, which no browser
      // exposes this way.
      expect(() => CameraPreferences(zoom: 0.5), throwsAssertionError);
    });

    test('two instances describing the same camera are equal', () {
      // OmniWebScanner reopens the camera when these compare unequal, so an
      // instance rebuilt from the same arguments has to compare equal or the
      // session is torn down and restarted on every rebuild.
      expect(CameraPreferences(), CameraPreferences());
      expect(CameraPreferences().hashCode, CameraPreferences().hashCode);
      expect(
        CameraPreferences.forMode(ScanMode.barcode),
        CameraPreferences.forMode(ScanMode.barcode),
      );
    });

    test('a differently tuned camera is not equal', () {
      expect(
        CameraPreferences(),
        isNot(CameraPreferences(tryHarder: false)),
      );
      expect(
        CameraPreferences(),
        isNot(CameraPreferences.forMode(ScanMode.barcode)),
      );
    });

    test('rejects a decode region that is not a fraction of the frame', () {
      expect(() => CameraPreferences(roiWidthFactor: 0), throwsAssertionError);
      expect(
          () => CameraPreferences(roiHeightFactor: 1.5), throwsAssertionError);
    });
  });

  group('ScanValidation', () {
    test('confirms twice for 1D and once for 2D', () {
      expect(ScanValidation.forMode(ScanMode.barcode).confirmations, 2);
      expect(ScanValidation.forMode(ScanMode.all).confirmations, 2);
      // Reed-Solomon error correction already makes a single QR read
      // trustworthy; a second confirmation would only add latency.
      expect(ScanValidation.forMode(ScanMode.qrCode).confirmations, 1);
    });

    test('presets trade latency against trust in the documented direction', () {
      expect(ScanValidation.none.confirmations, 1);
      expect(ScanValidation.none.requireChecksum, isFalse);
      expect(ScanValidation.strict.confirmations, 3);
      expect(ScanValidation.strict.requireChecksum, isTrue);
    });

    test('allowsFormat accepts everything when unrestricted', () {
      const unrestricted = ScanValidation();

      expect(unrestricted.allowsFormat(BarcodeFormat.qrCode), isTrue);
      expect(unrestricted.allowsFormat(BarcodeFormat.ean13), isTrue);
    });

    test('allowsFormat enforces an explicit set', () {
      const restricted = ScanValidation(
        allowedFormats: {BarcodeFormat.ean13, BarcodeFormat.ean8},
      );

      expect(restricted.allowsFormat(BarcodeFormat.ean8), isTrue);
      expect(restricted.allowsFormat(BarcodeFormat.qrCode), isFalse);
    });

    test('rejects a configuration that could never emit', () {
      expect(() => ScanValidation(confirmations: 0), throwsAssertionError);
      expect(() => ScanValidation(minLength: -1), throwsAssertionError);
    });

    test('two instances describing the same rules are equal', () {
      expect(ScanValidation(), ScanValidation());
      expect(ScanValidation().hashCode, ScanValidation().hashCode);

      // A Set compares by identity on its own, which would leave two rules
      // allowing exactly the same formats unequal.
      expect(
        ScanValidation(allowedFormats: {BarcodeFormat.ean13}),
        ScanValidation(allowedFormats: {BarcodeFormat.ean13}),
      );
      expect(
        ScanValidation(allowedFormats: {BarcodeFormat.ean13}),
        isNot(ScanValidation(allowedFormats: {BarcodeFormat.ean8})),
      );
    });

    test('the same guard kept still leaves two rules equal', () {
      // A closure can only be compared by identity, so a guard hoisted out of
      // a build method holds still and one written inline does not.
      bool guard(String value, BarcodeFormat format) => true;

      expect(ScanValidation(guard: guard), ScanValidation(guard: guard));
      expect(ScanValidation(guard: guard), isNot(ScanValidation()));
    });

    test('copyWith preserves the guard it was not asked to change', () {
      bool guard(String value, BarcodeFormat format) => true;
      final validation = ScanValidation(guard: guard).copyWith(minLength: 4);

      expect(validation.guard, same(guard));
      expect(validation.minLength, 4);
    });
  });

  group('ScannerOverlayStyle', () {
    test('frames a linear barcode in a band and a 2D code in a square', () {
      final linear = ScannerOverlayStyle.forMode(ScanMode.barcode);
      final square = ScannerOverlayStyle.forMode(ScanMode.qrCode);

      expect(linear.squareCutOut, isFalse);
      expect(square.squareCutOut, isTrue);
    });

    test('draws both modes with the same frame', () {
      // The window's shape is the only thing the mode is allowed to change.
      // Anything else diverging is what made 1.x ship two overlay widgets.
      final linear = ScannerOverlayStyle.forMode(ScanMode.barcode);
      final square = ScannerOverlayStyle.forMode(ScanMode.qrCode);

      expect(square.borderColor, linear.borderColor);
      expect(square.borderLength, linear.borderLength);
      expect(square.borderWidth, linear.borderWidth);
      expect(square.borderRadius, linear.borderRadius);
      expect(square.overlayColor, linear.overlayColor);
      expect(square.scanLineColor, linear.scanLineColor);
      expect(square.showScanLine, linear.showScanLine);
    });

    test('measures a square window against the preview it has to fit', () {
      const square = ScannerOverlayStyle(squareCutOut: true);

      // Portrait: the width is the tighter axis.
      expect(square.cutOutSizeFor(const Size(400, 800)), const Size(280, 280));
      // Landscape: a square taken from the width would not fit the height, and
      // the shape would clamp it back into a rectangle.
      expect(square.cutOutSizeFor(const Size(1200, 600)), const Size(420, 420));
    });

    test('leaves the barcode window as wide as the factor allows', () {
      const linear = ScannerOverlayStyle();

      expect(
        linear.cutOutSizeFor(const Size(400, 800)),
        Size(400 * linear.cutOutWidthFactor, linear.cutOutHeight),
      );
    });

    test('animates the scan line by default', () {
      const style = ScannerOverlayStyle();

      expect(style.showScanLine, isTrue);
      expect(style.scanLineDuration, greaterThan(Duration.zero));
    });

    test('copyWith keeps the rest of the style intact', () {
      const style = ScannerOverlayStyle(squareCutOut: true);
      final quiet = style.copyWith(showScanLine: false, cutOutHeight: 200);

      expect(quiet.showScanLine, isFalse);
      expect(quiet.cutOutHeight, 200);
      expect(quiet.squareCutOut, isTrue);
      expect(quiet.borderColor, style.borderColor);
      expect(quiet.overlayColor, style.overlayColor);
    });

    test('two identical styles are equal', () {
      // The overlay rebuilds its shape from the style, and ShapeDecoration
      // compares shapes to decide whether to repaint the dimmed area.
      expect(ScannerOverlayStyle(), ScannerOverlayStyle());
      expect(ScannerOverlayStyle().hashCode, ScannerOverlayStyle().hashCode);
      expect(
        ScannerOverlayStyle(),
        isNot(ScannerOverlayStyle(squareCutOut: true)),
      );
    });

    test('rejects a cut-out that cannot be drawn', () {
      expect(
        () => ScannerOverlayStyle(cutOutWidthFactor: 0),
        throwsAssertionError,
      );
      expect(
        () => ScannerOverlayStyle(cutOutWidthFactor: 1.5),
        throwsAssertionError,
      );
      expect(() => ScannerOverlayStyle(cutOutHeight: 0), throwsAssertionError);
    });
  });

  group('BarcodeResult', () {
    test('compares on payload and symbology, not on how it was confirmed', () {
      const first = BarcodeResult(
        value: '5901234123457',
        format: BarcodeFormat.ean13,
        confirmations: 2,
      );
      const second = BarcodeResult(
        value: '5901234123457',
        format: BarcodeFormat.ean13,
        confirmations: 3,
        checksumVerified: true,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('differs when the same text arrives from another symbology', () {
      const asEan = BarcodeResult(
        value: '5901234123457',
        format: BarcodeFormat.ean13,
      );
      const asQr = BarcodeResult(
        value: '5901234123457',
        format: BarcodeFormat.qrCode,
      );

      expect(asEan, isNot(asQr));
    });

    test('copyWith carries the untouched fields forward', () {
      const result = BarcodeResult(
        value: '5901234123457',
        format: BarcodeFormat.ean13,
        rawFormat: 'EAN_13',
        checksumVerified: true,
      );

      final copy = result.copyWith(confirmations: 3);

      expect(copy.rawFormat, 'EAN_13');
      expect(copy.checksumVerified, isTrue);
      expect(copy.confirmations, 3);
    });
  });
}
