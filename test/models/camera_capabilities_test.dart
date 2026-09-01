import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_scanner/flutter_web_scanner.dart';

void main() {
  group('CapabilityRange.tryParse', () {
    test('reads a MediaSettingsRange map', () {
      final range = CapabilityRange.tryParse({'min': 0.05, 'max': 8.0});

      expect(range?.min, 0.05);
      expect(range?.max, 8.0);
      expect(range?.step, isNull);
    });

    test('keeps a positive step and drops a meaningless one', () {
      expect(
        CapabilityRange.tryParse({'min': 1, 'max': 4, 'step': 0.5})?.step,
        0.5,
      );
      expect(
        CapabilityRange.tryParse({'min': 1, 'max': 4, 'step': 0})?.step,
        isNull,
      );
    });

    test('accepts a bare number as a fixed range', () {
      // Some browsers report a plain value where the spec says range.
      final range = CapabilityRange.tryParse(2.5);

      expect(range?.min, 2.5);
      expect(range?.max, 2.5);
      expect(range?.isFixed, isTrue);
    });

    test('returns null for anything unusable', () {
      expect(CapabilityRange.tryParse(null), isNull);
      expect(CapabilityRange.tryParse('near'), isNull);
      expect(CapabilityRange.tryParse(double.nan), isNull);
      expect(CapabilityRange.tryParse(double.infinity), isNull);
      // A capability reported with only half the interval is not usable.
      expect(CapabilityRange.tryParse({'min': 1}), isNull);
      // An inverted interval means the browser is confused; degrade instead of
      // acting on it.
      expect(CapabilityRange.tryParse({'min': 4, 'max': 1}), isNull);
    });
  });

  group('CapabilityRange.normalize', () {
    test('clamps into the interval', () {
      const range = CapabilityRange(min: 1, max: 4);

      expect(range.normalize(0.5), 1);
      expect(range.normalize(9), 4);
      expect(range.normalize(2), 2);
    });

    test('snaps to the nearest step without escaping the interval', () {
      const range = CapabilityRange(min: 1, max: 4, step: 0.5);

      expect(range.normalize(2.3), 2.5);
      expect(range.normalize(3.9), 4.0);
    });

    test('contains reports interval membership', () {
      const range = CapabilityRange(min: 1, max: 4);

      expect(range.contains(1), isTrue);
      expect(range.contains(4), isTrue);
      expect(range.contains(4.1), isFalse);
    });

    test('compares by value', () {
      expect(
        const CapabilityRange(min: 1, max: 4),
        const CapabilityRange(min: 1, max: 4),
      );
      expect(
        const CapabilityRange(min: 1, max: 4),
        isNot(const CapabilityRange(min: 1, max: 4, step: 0.5)),
      );
    });
  });

  group('CameraCapabilities', () {
    test('reports whether the lens reaches a close subject', () {
      const close = CameraCapabilities(
        focusDistance: CapabilityRange(min: 0.03, max: 10),
      );
      const far = CameraCapabilities(
        focusDistance: CapabilityRange(min: 0.30, max: 10),
      );

      expect(close.canFocusCloserThan(0.10), isTrue);
      expect(far.canFocusCloserThan(0.10), isFalse);
      // Null, not false: "we do not know" must stay distinguishable from
      // "it cannot", since the selector weighs them differently.
      expect(CameraCapabilities.unknown.canFocusCloserThan(0.10), isNull);
    });

    test('exposes sensor area only when both dimensions are known', () {
      expect(
        const CameraCapabilities(maxWidth: 1920, maxHeight: 1080).maxPixels,
        1920 * 1080,
      );
      expect(const CameraCapabilities(maxWidth: 1920).maxPixels, isNull);
      expect(CameraCapabilities.unknown.maxPixels, isNull);
    });

    test('detects continuous focus support', () {
      expect(
        const CameraCapabilities(
          focusModes: ['manual', 'continuous'],
        ).supportsContinuousFocus,
        isTrue,
      );
      expect(
        const CameraCapabilities(
          focusModes: ['manual'],
        ).supportsContinuousFocus,
        isFalse,
      );
    });

    group('mergeWith', () {
      test('prefers measured values over enumerated ones', () {
        const enumerated = CameraCapabilities(
          facing: CameraFacing.back,
          maxWidth: 1280,
          maxHeight: 720,
        );
        const measured = CameraCapabilities(
          focusDistance: CapabilityRange(min: 0.03, max: 10),
          maxWidth: 4032,
          maxHeight: 3024,
          focusModes: ['continuous'],
          supportsTorch: true,
        );

        final merged = enumerated.mergeWith(measured);

        expect(merged.maxWidth, 4032);
        expect(merged.focusDistance?.min, 0.03);
        expect(merged.supportsTorch, isTrue);
        // The live track never reports facingMode, so the enumeration-time
        // value has to survive the merge.
        expect(merged.facing, CameraFacing.back);
      });

      test('keeps what only the first side knew', () {
        const enumerated = CameraCapabilities(
          facing: CameraFacing.back,
          maxWidth: 1280,
          maxHeight: 720,
          focusModes: ['single-shot'],
        );

        final merged = enumerated.mergeWith(CameraCapabilities.unknown);

        expect(merged.facing, CameraFacing.back);
        expect(merged.maxWidth, 1280);
        expect(merged.focusModes, ['single-shot']);
      });

      test('never downgrades a torch that was already reported', () {
        const withTorch = CameraCapabilities(supportsTorch: true);

        expect(
          withTorch.mergeWith(CameraCapabilities.unknown).supportsTorch,
          isTrue,
        );
      });
    });
  });

  group('CameraModel', () {
    test('folds probed capabilities in without losing the label', () {
      const camera = CameraModel(
        deviceId: 'back-1',
        label: 'Back Ultra Wide Camera',
        capabilities: CameraCapabilities(facing: CameraFacing.back),
      );

      final refined = camera.withCapabilities(
        const CameraCapabilities(
          focusDistance: CapabilityRange(min: 0.03, max: 10),
        ),
      );

      expect(refined.label, 'Back Ultra Wide Camera');
      expect(refined.facing, CameraFacing.back);
      expect(refined.capabilities.focusDistance?.min, 0.03);
    });

    test('identity ignores capabilities, so a probe does not create a new '
        'device', () {
      const camera = CameraModel(deviceId: 'back-1', label: 'Back Camera');
      final probed = camera.withCapabilities(
        const CameraCapabilities(supportsTorch: true),
      );

      expect(probed, camera);
      expect(probed.hashCode, camera.hashCode);
    });

    test('treats a blank label as absent', () {
      expect(const CameraModel(deviceId: 'a', label: '   ').hasLabel, isFalse);
      expect(const CameraModel(deviceId: 'a', label: 'Cam').hasLabel, isTrue);
    });
  });

  group('CameraFacing.fromConstraint', () {
    test('maps the spec facingMode values', () {
      expect(CameraFacing.fromConstraint('user'), CameraFacing.front);
      expect(CameraFacing.fromConstraint('environment'), CameraFacing.back);
      expect(CameraFacing.fromConstraint('left'), CameraFacing.external);
      expect(CameraFacing.fromConstraint('right'), CameraFacing.external);
    });

    test('degrades to unknown for anything else', () {
      expect(CameraFacing.fromConstraint(null), CameraFacing.unknown);
      expect(CameraFacing.fromConstraint('rear'), CameraFacing.unknown);
    });
  });
}
