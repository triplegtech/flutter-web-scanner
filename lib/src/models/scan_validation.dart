import 'package:flutter/foundation.dart' show setEquals;
import 'package:omni_qrcode_barcode_web_reader/src/enums/barcode_format.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_mode.dart';

/// Signature for an application-specific check applied after the built-in ones.
///
/// Return `false` to reject the read and keep scanning.
typedef BarcodeGuard = bool Function(String value, BarcodeFormat format);

/// Rules applied to a raw decode before it is surfaced through `onDetect`.
///
/// A camera stream produces dozens of decode attempts per second on partially
/// visible, motion-blurred symbols. Engines will happily return a syntactically
/// valid but wrong payload from a half-covered 1D barcode. These rules are what
/// separate "the engine returned something" from "we trust this value".
class ScanValidation {
  const ScanValidation({
    this.requireChecksum = true,
    this.confirmations = 2,
    this.confirmationWindow = const Duration(milliseconds: 1500),
    this.cooldown = const Duration(milliseconds: 1500),
    this.minLength = 1,
    this.allowedFormats,
    this.guard,
  })  : assert(confirmations >= 1, 'confirmations must be at least 1'),
        assert(minLength >= 0, 'minLength cannot be negative');

  /// Verify the check digit for formats that carry one (EAN/UPC/ITF).
  ///
  /// Cheap and catches the most common misread mode on 1D symbols, so it is on
  /// by default. Has no effect on formats without a checksum.
  final bool requireChecksum;

  /// Identical consecutive reads required before emitting.
  ///
  /// `1` emits on first decode. `2` is the default and removes nearly all
  /// transient misreads at the cost of roughly one extra frame of latency.
  final int confirmations;

  /// How long a partial confirmation streak stays alive.
  ///
  /// If [confirmations] is not reached within this window the streak resets,
  /// so a stale read from seconds ago cannot combine with a fresh one.
  final Duration confirmationWindow;

  /// How long the same value is suppressed after being emitted.
  ///
  /// Prevents a code lingering in frame from firing `onDetect` on every frame.
  final Duration cooldown;

  /// Reject payloads shorter than this.
  final int minLength;

  /// Restrict accepted symbologies beyond what [ScanMode] already hints.
  ///
  /// The mode hint is advisory — engines can and do return formats outside it —
  /// so this is the enforcing counterpart. `null` accepts whatever the mode
  /// allows.
  final Set<BarcodeFormat>? allowedFormats;

  /// Application-specific check, e.g. verifying a GTIN prefix or a batch
  /// number pattern.
  final BarcodeGuard? guard;

  /// Defaults tuned for [mode].
  ///
  /// 2D symbologies carry Reed-Solomon error correction, so a single decode is
  /// already trustworthy and a second confirmation only adds latency. 1D
  /// symbologies have no such protection and are confirmed twice.
  factory ScanValidation.forMode(ScanMode mode) => switch (mode) {
        ScanMode.qrCode => const ScanValidation(confirmations: 1),
        ScanMode.barcode || ScanMode.all => const ScanValidation(),
      };

  /// Emit on first decode with no checks. Lowest latency, lowest trust.
  static const ScanValidation none = ScanValidation(
    requireChecksum: false,
    confirmations: 1,
    cooldown: Duration(milliseconds: 1000),
  );

  /// Three confirmations and mandatory checksums, for noisy environments or
  /// high-cost misreads.
  static const ScanValidation strict = ScanValidation(
    confirmations: 3,
    confirmationWindow: Duration(milliseconds: 2000),
  );

  /// Whether [format] is permitted by [allowedFormats].
  bool allowsFormat(BarcodeFormat format) {
    final allowed = allowedFormats;
    return allowed == null || allowed.contains(format);
  }

  ScanValidation copyWith({
    bool? requireChecksum,
    int? confirmations,
    Duration? confirmationWindow,
    Duration? cooldown,
    int? minLength,
    Set<BarcodeFormat>? allowedFormats,
    BarcodeGuard? guard,
  }) {
    return ScanValidation(
      requireChecksum: requireChecksum ?? this.requireChecksum,
      confirmations: confirmations ?? this.confirmations,
      confirmationWindow: confirmationWindow ?? this.confirmationWindow,
      cooldown: cooldown ?? this.cooldown,
      minLength: minLength ?? this.minLength,
      allowedFormats: allowedFormats ?? this.allowedFormats,
      guard: guard ?? this.guard,
    );
  }

  // Compared by OmniWebScanner to decide whether the camera has to be
  // reopened, so an equal-but-rebuilt instance must not read as a change. See
  // the note on [CameraPreferences.==].
  //
  // [guard] is compared by identity because a closure cannot be compared any
  // other way: a guard rebuilt inside a build method is a different object and
  // does count as a change. Hoist it to a top-level or static function to hold
  // that still.
  @override
  bool operator ==(Object other) =>
      other is ScanValidation &&
      other.requireChecksum == requireChecksum &&
      other.confirmations == confirmations &&
      other.confirmationWindow == confirmationWindow &&
      other.cooldown == cooldown &&
      other.minLength == minLength &&
      setEquals(other.allowedFormats, allowedFormats) &&
      other.guard == guard;

  @override
  int get hashCode => Object.hash(
        requireChecksum,
        confirmations,
        confirmationWindow,
        cooldown,
        minLength,
        // A Set's own hashCode is identity-based, so it would undo everything
        // setEquals establishes above.
        allowedFormats == null
            ? null
            : Object.hashAllUnordered(allowedFormats!),
        guard,
      );
}
