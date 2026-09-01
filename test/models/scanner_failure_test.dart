import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_scanner/flutter_web_scanner.dart';

void main() {
  group('kindFromDomError', () {
    test('classifies a denied permission, including legacy spellings', () {
      // Older Safari and Firefox still emit the pre-spec names.
      for (final name in [
        'NotAllowedError',
        'PermissionDeniedError',
        'SecurityError',
      ]) {
        expect(
          ScannerFailure.kindFromDomError(name),
          ScannerFailureKind.permissionDenied,
          reason: name,
        );
      }
    });

    test('classifies a missing device', () {
      expect(
        ScannerFailure.kindFromDomError('NotFoundError'),
        ScannerFailureKind.noCameraFound,
      );
      expect(
        ScannerFailure.kindFromDomError('DevicesNotFoundError'),
        ScannerFailureKind.noCameraFound,
      );
    });

    test('classifies a camera held by another app', () {
      for (final name in [
        'NotReadableError',
        'TrackStartError',
        'AbortError',
      ]) {
        expect(
          ScannerFailure.kindFromDomError(name),
          ScannerFailureKind.cameraInUse,
          reason: name,
        );
      }
    });

    test('classifies unsatisfiable constraints', () {
      expect(
        ScannerFailure.kindFromDomError('OverconstrainedError'),
        ScannerFailureKind.overconstrained,
      );
      expect(
        ScannerFailure.kindFromDomError('ConstraintNotSatisfiedError'),
        ScannerFailureKind.overconstrained,
      );
    });

    test('tolerates the whitespace some browsers pad the name with', () {
      expect(
        ScannerFailure.kindFromDomError(' NotAllowedError '),
        ScannerFailureKind.permissionDenied,
      );
    });

    test('falls back to unknown rather than guessing', () {
      expect(ScannerFailure.kindFromDomError(null), ScannerFailureKind.unknown);
      expect(
        ScannerFailure.kindFromDomError('SomethingNewError'),
        ScannerFailureKind.unknown,
      );
    });
  });

  group('isRetryable', () {
    test('offers a retry only where one could actually succeed', () {
      const retryable = {
        ScannerFailureKind.cameraInUse,
        ScannerFailureKind.overconstrained,
        ScannerFailureKind.startFailed,
        ScannerFailureKind.unknown,
      };

      for (final kind in ScannerFailureKind.values) {
        expect(
          ScannerFailure(kind, 'x').isRetryable,
          retryable.contains(kind),
          reason: kind.name,
        );
      }
    });
  });

  test('toString names the kind, for logs and bug reports', () {
    const failure = ScannerFailure(
      ScannerFailureKind.cameraInUse,
      'NotReadableError',
    );

    expect(failure.toString(), contains('cameraInUse'));
    expect(failure.toString(), contains('NotReadableError'));
  });
}
