import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_scanner/flutter_web_scanner.dart';

CameraModel camera(
  String label, {
  String? deviceId,
  int order = 0,
  CameraCapabilities capabilities = CameraCapabilities.unknown,
}) {
  return CameraModel(
    deviceId: deviceId ?? label.toLowerCase().replaceAll(' ', '-'),
    label: label,
    order: order,
    capabilities: capabilities,
  );
}

CameraCapabilities caps({
  CameraFacing facing = CameraFacing.unknown,
  double? minFocusMetres,
  int? width,
  int? height,
  List<String> focusModes = const <String>[],
}) {
  return CameraCapabilities(
    facing: facing,
    focusDistance: minFocusMetres == null
        ? null
        : CapabilityRange(min: minFocusMetres, max: 5),
    maxWidth: width,
    maxHeight: height,
    focusModes: focusModes,
  );
}

List<String> rankedLabels(
  List<CameraModel> cameras, {
  ScanMode mode = ScanMode.barcode,
  CameraPreferences preferences = const CameraPreferences(),
}) {
  return CameraSelector.rank(
    cameras,
    mode: mode,
    preferences: preferences,
  ).map((candidate) => candidate.camera.label).toList();
}

void main() {
  group('inferFacing', () {
    test('recognises front cameras across languages', () {
      for (final label in [
        'Front Camera',
        'Câmera Frontal',
        'FaceTime HD Camera',
        'Cámara delantera',
        'Caméra avant',
      ]) {
        expect(
          CameraSelector.inferFacing(label),
          CameraFacing.front,
          reason: label,
        );
      }
    });

    test('recognises rear cameras across languages', () {
      for (final label in [
        'Back Camera',
        'Câmera Traseira',
        'Rear Camera',
        'Cámara trasera',
        'Rückkamera',
      ]) {
        expect(
          CameraSelector.inferFacing(label),
          CameraFacing.back,
          reason: label,
        );
      }
    });

    test('returns unknown for an empty label', () {
      expect(CameraSelector.inferFacing(''), CameraFacing.unknown);
    });
  });

  group('inferLens', () {
    test('prefers the more specific ultra-wide match over wide', () {
      expect(
        CameraSelector.inferLens('Back Ultra Wide Camera'),
        LensKind.ultraWide,
      );
      expect(
        CameraSelector.inferLens('Câmera Grande Angular Traseira'),
        LensKind.ultraWide,
      );
    });

    test('identifies the main lens', () {
      expect(CameraSelector.inferLens('Back Wide Camera'), LensKind.main);
    });

    test('identifies telephoto and depth sensors', () {
      expect(
        CameraSelector.inferLens('Back Telephoto Camera'),
        LensKind.telephoto,
      );
      expect(
        CameraSelector.inferLens('Front TrueDepth Camera'),
        LensKind.depth,
      );
    });

    test('collapses whitespace variations', () {
      expect(
        CameraSelector.inferLens('Back   Ultra  Wide   Camera'),
        LensKind.ultraWide,
      );
    });
  });

  group('rank', () {
    test('puts a rear camera ahead of a front one', () {
      final ranked = rankedLabels([
        camera('Front Camera'),
        camera('Back Camera'),
      ]);
      expect(ranked.first, 'Back Camera');
    });

    test('still returns a front-only device instead of an empty list', () {
      // 1.x dropped every front-facing camera during scoring, so a laptop or
      // tablet with only a selfie camera surfaced as "no camera found".
      final ranked = CameraSelector.rank(
        [camera('FaceTime HD Camera')],
        mode: ScanMode.qrCode,
        preferences: const CameraPreferences(),
      );
      expect(ranked, hasLength(1));
      expect(ranked.first.facing, CameraFacing.front);
    });

    test('never returns fewer cameras than it was given', () {
      final cameras = [
        camera('Front Camera'),
        camera('Back Ultra Wide Camera'),
        camera('Back TrueDepth Camera'),
      ];
      expect(
        CameraSelector.rank(
          cameras,
          mode: ScanMode.barcode,
          preferences: const CameraPreferences(),
        ),
        hasLength(cameras.length),
      );
    });

    test('ranks a depth sensor last, since it cannot produce a decodable '
        'image', () {
      final ranked = rankedLabels([
        camera('Back TrueDepth Camera'),
        camera('Back Wide Camera'),
      ]);
      expect(ranked.last, 'Back TrueDepth Camera');
    });

    test('does not read an ultra-wide label as evidence of close focus', () {
      // Ultra-wide is the macro lens inside the iOS camera app, never through
      // getUserMedia, and is fixed-focus on most Android hardware. Betting on
      // the label made barcode mode — which scans at this distance — select a
      // worse lens than QR mode did, on real Android and iOS devices.
      final ranked = rankedLabels([
        camera('Back Wide Camera'),
        camera('Back Ultra Wide Camera'),
      ], preferences: const CameraPreferences(distance: ScanDistance.near));
      expect(ranked.first, 'Back Wide Camera');
    });

    test('still takes an ultra-wide measured to focus closer', () {
      // The label is not evidence; a measurement is. This is the case the
      // near-range preset exists for, and it has to keep working.
      final ranked = rankedLabels([
        camera('Back Wide Camera', capabilities: caps(minFocusMetres: 0.10)),
        camera(
          'Back Ultra Wide Camera',
          capabilities: caps(minFocusMetres: 0.02),
        ),
      ], preferences: const CameraPreferences(distance: ScanDistance.near));
      expect(ranked.first, 'Back Ultra Wide Camera');
    });

    test('picks the same lens for a barcode as for a QR code held close', () {
      // The symptom that started this: the two modes use different
      // ScanDistance presets, and they disagreed about which lens sees a code
      // held close to the phone.
      const cameras = ['Back Wide Camera', 'Back Ultra Wide Camera'];

      expect(
        rankedLabels(
          [camera(cameras[0]), camera(cameras[1])],
          mode: ScanMode.barcode,
          preferences: CameraPreferences.forMode(ScanMode.barcode),
        ).first,
        rankedLabels(
          [camera(cameras[0]), camera(cameras[1])],
          mode: ScanMode.qrCode,
          preferences: CameraPreferences.forMode(ScanMode.qrCode),
        ).first,
      );
    });

    test('prefers the main lens at normal range, where ultra-wide distortion '
        'hurts 1D decoding', () {
      final ranked = rankedLabels([
        camera('Back Ultra Wide Camera'),
        camera('Back Wide Camera'),
      ], preferences: const CameraPreferences(distance: ScanDistance.normal));
      expect(ranked.first, 'Back Wide Camera');
    });

    test('prefers the main lens in auto mode when nothing is measured', () {
      final ranked = rankedLabels([
        camera('Back Ultra Wide Camera'),
        camera('Back Wide Camera'),
      ], preferences: const CameraPreferences());
      expect(ranked.first, 'Back Wide Camera');
    });

    test('lets a measured focus distance overturn the label-based guess', () {
      // The whole point of probing: the main lens looks better on paper, but
      // it physically cannot focus on a code held 5 cm away.
      final ranked = rankedLabels([
        camera('Back Wide Camera', capabilities: caps(minFocusMetres: 0.30)),
        camera(
          'Back Ultra Wide Camera',
          capabilities: caps(minFocusMetres: 0.03),
        ),
      ], preferences: const CameraPreferences());
      expect(ranked.first, 'Back Ultra Wide Camera');
    });

    test('trusts a reported facing mode over a misleading label', () {
      // Some vendors label the rear camera "camera2" with no direction at all,
      // while Chromium reports facingMode accurately.
      final ranked = rankedLabels([
        camera('camera1', capabilities: caps(facing: CameraFacing.front)),
        camera('camera2', capabilities: caps(facing: CameraFacing.back)),
      ]);
      expect(ranked.first, 'camera2');
    });

    test('prefers the higher-resolution sensor when all else is equal', () {
      final ranked = rankedLabels([
        camera(
          'Back Wide Camera A',
          capabilities: caps(width: 640, height: 480),
        ),
        camera(
          'Back Wide Camera B',
          capabilities: caps(width: 1920, height: 1080),
        ),
      ]);
      expect(ranked.first, 'Back Wide Camera B');
    });

    test('rewards continuous focus support', () {
      final ranked = rankedLabels([
        camera('Back Wide Camera A'),
        camera(
          'Back Wide Camera B',
          capabilities: caps(focusModes: const ['continuous']),
        ),
      ]);
      expect(ranked.first, 'Back Wide Camera B');
    });

    test('breaks ties by enumeration order rather than alphabetically', () {
      // 1.x re-sorted the Android list alphabetically by label, discarding the
      // score it had just computed.
      final ranked = rankedLabels([
        camera('Zulu Back Camera', order: 0),
        camera('Alpha Back Camera', order: 1),
      ]);
      expect(ranked.first, 'Zulu Back Camera');
    });

    test('records a human-readable score breakdown', () {
      final ranked = CameraSelector.rank(
        [camera('Back Ultra Wide Camera')],
        mode: ScanMode.barcode,
        preferences: const CameraPreferences(distance: ScanDistance.near),
      );
      expect(ranked.first.reasons, isNotEmpty);
      expect(ranked.first.reasons.join(' '), contains('rear-facing'));
    });
  });

  group('probeTargets', () {
    List<CameraCandidate> rank(
      List<CameraModel> cameras, [
      CameraPreferences preferences = const CameraPreferences(),
    ]) {
      return CameraSelector.rank(
        cameras,
        mode: ScanMode.barcode,
        preferences: preferences,
      );
    }

    test('returns nothing when probing is disabled', () {
      final ranked = rank([camera('Back Wide Camera')]);
      expect(
        CameraSelector.probeTargets(
          ranked,
          const CameraPreferences(probeCapabilities: false),
        ),
        isEmpty,
      );
    });

    test('caps the number of cameras probed', () {
      final ranked = rank([
        camera('Back Wide Camera', order: 0),
        camera('Back Ultra Wide Camera', order: 1),
        camera('Back Telephoto Camera', order: 2),
      ]);
      expect(
        CameraSelector.probeTargets(
          ranked,
          const CameraPreferences(maxProbedCameras: 2),
        ),
        hasLength(2),
      );
    });

    test('skips front cameras and depth sensors', () {
      final ranked = rank([
        camera('Back Wide Camera'),
        camera('Front Camera'),
        camera('Back TrueDepth Camera'),
      ]);
      final targets = CameraSelector.probeTargets(
        ranked,
        const CameraPreferences(),
      );
      expect(targets.map((c) => c.label), ['Back Wide Camera']);
    });

    test('skips cameras whose focus distance is already known', () {
      final ranked = rank([
        camera('Back Wide Camera', capabilities: caps(minFocusMetres: 0.1)),
        camera('Back Ultra Wide Camera'),
      ]);
      final targets = CameraSelector.probeTargets(
        ranked,
        const CameraPreferences(),
      );
      expect(targets.map((c) => c.label), ['Back Ultra Wide Camera']);
    });
  });
}
