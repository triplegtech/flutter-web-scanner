import 'package:flutter_web_scanner/src/core/barcode_validator.dart';
import 'package:flutter_web_scanner/src/enums/barcode_format.dart';
import 'package:flutter_web_scanner/src/models/barcode_result.dart';
import 'package:flutter_web_scanner/src/models/scan_validation.dart';

/// What the stabiliser decided about a raw decode.
sealed class StabilizerDecision {
  const StabilizerDecision();
}

/// The read is trusted and should be surfaced to the caller.
final class StabilizerEmit extends StabilizerDecision {
  const StabilizerEmit(this.result);

  final BarcodeResult result;
}

/// The read is valid but has not been confirmed enough times yet.
final class StabilizerPending extends StabilizerDecision {
  const StabilizerPending({
    required this.value,
    required this.confirmations,
    required this.required,
  });

  final String value;
  final int confirmations;
  final int required;
}

/// The read was already emitted and is still within its cooldown.
final class StabilizerSuppressed extends StabilizerDecision {
  const StabilizerSuppressed(this.value);

  final String value;
}

/// The read failed validation.
final class StabilizerRejected extends StabilizerDecision {
  const StabilizerRejected(this.rejection);

  final ValidationRejected rejection;
}

/// Turns a noisy stream of raw decodes into trustworthy detections.
///
/// A live camera feeds the decoder tens of frames per second. Three things go
/// wrong without this layer, and all three were reachable in 1.x:
///
/// * A code sitting in frame fires `onDetect` on every single frame.
/// * A partially occluded or motion-blurred 1D symbol decodes to a wrong but
///   structurally valid payload, and is reported once and never contradicted.
/// * A stale read from seconds ago combines with a fresh one and looks like
///   confirmation.
///
/// The stabiliser holds a confirmation streak per value, expires it on an idle
/// timeout, validates before counting, and applies a per-value cooldown after
/// emitting. It owns no timers and reads time only through an injectable
/// [clock], so its behaviour is fully testable without waiting.
class DetectionStabilizer {
  DetectionStabilizer({required this.validation, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Rules every offered decode is measured against.
  ///
  /// Replaceable while decodes are arriving, and read fresh on each [offer], so
  /// a caller who rebuilds their [ScanValidation] does not have to restart the
  /// camera to change the rules. Streak and cooldown state is deliberately
  /// kept: swapping rules is not a restart, and a code emitted a moment ago
  /// must stay suppressed across one.
  ScanValidation validation;

  final DateTime Function() _clock;

  String? _streakValue;
  int _streakCount = 0;
  DateTime? _streakLastHit;

  /// Values emitted recently, mapped to when they were emitted.
  ///
  /// Keyed per value rather than tracking a single "last emitted" so that two
  /// codes alternating in frame do not clear each other's cooldown.
  final Map<String, DateTime> _cooldowns = <String, DateTime>{};

  /// Current confirmation count for the value being tracked, for diagnostics.
  int get pendingConfirmations => _streakCount;

  /// Offers a raw decode and returns what should happen with it.
  StabilizerDecision offer(String value, BarcodeFormat format) {
    final now = _clock();
    _expireCooldowns(now);

    final outcome = BarcodeValidator.validate(value, format, validation);
    if (outcome is ValidationRejected) {
      // A rejected read is evidence the current streak is unreliable, so drop
      // it rather than letting a valid read before and after a bad one add up.
      _clearStreak();
      return StabilizerRejected(outcome);
    }

    final emittedAt = _cooldowns[value];
    if (emittedAt != null) {
      return StabilizerSuppressed(value);
    }

    _advanceStreak(value, now);

    if (_streakCount < validation.confirmations) {
      return StabilizerPending(
        value: value,
        confirmations: _streakCount,
        required: validation.confirmations,
      );
    }

    final confirmations = _streakCount;
    _cooldowns[value] = now;
    _clearStreak();

    return StabilizerEmit(
      BarcodeResult(
        value: value,
        format: format,
        confirmations: confirmations,
        checksumVerified:
            outcome
                is ValidationAccepted //
            ? outcome.checksumVerified
            : false,
      ),
    );
  }

  /// Drops all streak and cooldown state.
  ///
  /// Call when the camera restarts, so a value read before the restart cannot
  /// suppress the same value read after it.
  void reset() {
    _clearStreak();
    _cooldowns.clear();
  }

  void _advanceStreak(String value, DateTime now) {
    final lastHit = _streakLastHit;
    final isSameValue = _streakValue == value;
    final isStale =
        lastHit == null ||
        now.difference(lastHit) > validation.confirmationWindow;

    if (isSameValue && !isStale) {
      _streakCount++;
    } else {
      _streakValue = value;
      _streakCount = 1;
    }
    _streakLastHit = now;
  }

  void _clearStreak() {
    _streakValue = null;
    _streakCount = 0;
    _streakLastHit = null;
  }

  void _expireCooldowns(DateTime now) {
    _cooldowns.removeWhere(
      (_, emittedAt) => now.difference(emittedAt) >= validation.cooldown,
    );
  }
}
