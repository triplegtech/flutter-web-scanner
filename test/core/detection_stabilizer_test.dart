import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_scanner/flutter_web_scanner.dart';
import 'package:flutter_web_scanner/src/core/detection_stabilizer.dart';

/// Hand-cranked clock, so confirmation windows and cooldowns are exercised
/// without any real waiting.
class _ManualClock {
  DateTime _now = DateTime.utc(2026, 1, 1);

  DateTime call() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}

void main() {
  late _ManualClock clock;

  setUp(() => clock = _ManualClock());

  DetectionStabilizer build([ScanValidation? validation]) {
    return DetectionStabilizer(
      validation: validation ?? const ScanValidation(),
      clock: clock.call,
    );
  }

  // A valid EAN-13 and a second, different valid one.
  const validEan = '5901234123457';
  const otherEan = '4006381333931';

  group('confirmation streak', () {
    test('withholds the first read when two confirmations are required', () {
      final stabilizer = build();
      final decision = stabilizer.offer(validEan, BarcodeFormat.ean13);

      expect(decision, isA<StabilizerPending>());
      expect((decision as StabilizerPending).confirmations, 1);
      expect(decision.required, 2);
    });

    test('emits on the second identical read', () {
      final stabilizer = build();
      stabilizer.offer(validEan, BarcodeFormat.ean13);
      final decision = stabilizer.offer(validEan, BarcodeFormat.ean13);

      expect(decision, isA<StabilizerEmit>());
      expect((decision as StabilizerEmit).result.value, validEan);
      expect(decision.result.confirmations, 2);
      expect(decision.result.checksumVerified, isTrue);
    });

    test('emits on the first read when only one confirmation is required', () {
      final stabilizer = build(const ScanValidation(confirmations: 1));
      expect(
        stabilizer.offer(validEan, BarcodeFormat.ean13),
        isA<StabilizerEmit>(),
      );
    });

    test('requires three reads under the strict preset', () {
      final stabilizer = build(ScanValidation.strict);
      expect(
        stabilizer.offer(validEan, BarcodeFormat.ean13),
        isA<StabilizerPending>(),
      );
      expect(
        stabilizer.offer(validEan, BarcodeFormat.ean13),
        isA<StabilizerPending>(),
      );
      expect(
        stabilizer.offer(validEan, BarcodeFormat.ean13),
        isA<StabilizerEmit>(),
      );
    });

    test('restarts the streak when a different value interrupts it', () {
      final stabilizer = build(ScanValidation.strict);
      stabilizer.offer(validEan, BarcodeFormat.ean13);
      stabilizer.offer(validEan, BarcodeFormat.ean13);
      stabilizer.offer(otherEan, BarcodeFormat.ean13);

      final decision = stabilizer.offer(validEan, BarcodeFormat.ean13);
      expect((decision as StabilizerPending).confirmations, 1);
    });

    test('expires a stale streak so old and new reads cannot combine', () {
      final stabilizer = build(
        const ScanValidation(confirmationWindow: Duration(milliseconds: 500)),
      );
      stabilizer.offer(validEan, BarcodeFormat.ean13);
      clock.advance(const Duration(milliseconds: 501));

      final decision = stabilizer.offer(validEan, BarcodeFormat.ean13);
      expect(
        decision,
        isA<StabilizerPending>(),
        reason: 'a read half a second later is not a confirmation',
      );
      expect((decision as StabilizerPending).confirmations, 1);
    });

    test('keeps the streak alive inside the confirmation window', () {
      final stabilizer = build(
        const ScanValidation(confirmationWindow: Duration(milliseconds: 500)),
      );
      stabilizer.offer(validEan, BarcodeFormat.ean13);
      clock.advance(const Duration(milliseconds: 499));

      expect(
        stabilizer.offer(validEan, BarcodeFormat.ean13),
        isA<StabilizerEmit>(),
      );
    });
  });

  group('cooldown', () {
    test('suppresses the same value while it is cooling down', () {
      final stabilizer = build(const ScanValidation(confirmations: 1));
      stabilizer.offer(validEan, BarcodeFormat.ean13);

      final decision = stabilizer.offer(validEan, BarcodeFormat.ean13);
      expect(decision, isA<StabilizerSuppressed>());
    });

    test('emits the same value again once the cooldown expires', () {
      final stabilizer = build(
        const ScanValidation(
          confirmations: 1,
          cooldown: Duration(milliseconds: 800),
        ),
      );
      stabilizer.offer(validEan, BarcodeFormat.ean13);
      clock.advance(const Duration(milliseconds: 800));

      expect(
        stabilizer.offer(validEan, BarcodeFormat.ean13),
        isA<StabilizerEmit>(),
      );
    });

    test('tracks cooldowns per value, so two codes in frame do not clear each '
        "other's", () {
      final stabilizer = build(const ScanValidation(confirmations: 1));
      stabilizer.offer(validEan, BarcodeFormat.ean13);

      expect(
        stabilizer.offer(otherEan, BarcodeFormat.ean13),
        isA<StabilizerEmit>(),
        reason: 'a different code is a genuinely new detection',
      );
      expect(
        stabilizer.offer(validEan, BarcodeFormat.ean13),
        isA<StabilizerSuppressed>(),
        reason: 'the first code is still cooling down',
      );
    });
  });

  group('validation', () {
    test('rejects a payload that fails its check digit', () {
      final stabilizer = build();
      final decision = stabilizer.offer('5901234123458', BarcodeFormat.ean13);

      expect(decision, isA<StabilizerRejected>());
      expect(
        (decision as StabilizerRejected).rejection.reason,
        BarcodeRejection.checksumMismatch,
      );
    });

    test('a rejected read never counts toward confirmation', () {
      final stabilizer = build();
      stabilizer.offer('5901234123458', BarcodeFormat.ean13);
      stabilizer.offer('5901234123458', BarcodeFormat.ean13);

      expect(stabilizer.pendingConfirmations, 0);
    });

    test('a rejected read invalidates the streak around it', () {
      final stabilizer = build();
      stabilizer.offer(validEan, BarcodeFormat.ean13);
      stabilizer.offer('bad-read', BarcodeFormat.ean13);

      final decision = stabilizer.offer(validEan, BarcodeFormat.ean13);
      expect(
        decision,
        isA<StabilizerPending>(),
        reason: 'a misread between two good ones means the frame was unstable',
      );
    });
  });

  group('reset', () {
    test('clears streaks and cooldowns so a restart can re-emit', () {
      final stabilizer = build(const ScanValidation(confirmations: 1));
      stabilizer.offer(validEan, BarcodeFormat.ean13);
      stabilizer.reset();

      expect(
        stabilizer.offer(validEan, BarcodeFormat.ean13),
        isA<StabilizerEmit>(),
      );
    });
  });
}
