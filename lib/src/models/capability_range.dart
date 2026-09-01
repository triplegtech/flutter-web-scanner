import 'dart:math' as math;

/// A numeric capability range as reported by `MediaStreamTrack.getCapabilities`.
///
/// Mirrors the `MediaSettingsRange` dictionary: a closed `[min, max]` interval
/// with an optional quantisation [step].
class CapabilityRange {
  const CapabilityRange({required this.min, required this.max, this.step});

  final double min;
  final double max;
  final double? step;

  /// Parses a `MediaSettingsRange`-shaped map, returning `null` when the
  /// browser omitted the capability or reported it malformed.
  ///
  /// Browsers are inconsistent here — some report a bare number instead of a
  /// range, others report `min == max` for a fixed value — so anything that
  /// cannot be read as a usable interval degrades to `null` rather than
  /// throwing.
  static CapabilityRange? tryParse(Object? raw) {
    if (raw is num) {
      final value = raw.toDouble();
      if (!value.isFinite) return null;
      return CapabilityRange(min: value, max: value);
    }
    if (raw is! Map) return null;
    final min = (raw['min'] as num?)?.toDouble();
    final max = (raw['max'] as num?)?.toDouble();
    if (min == null || max == null) return null;
    if (!min.isFinite || !max.isFinite || max < min) return null;
    final step = (raw['step'] as num?)?.toDouble();
    return CapabilityRange(
      min: min,
      max: max,
      step: step != null && step.isFinite && step > 0 ? step : null,
    );
  }

  /// Clamps [value] into the range and snaps it to [step] when one is known.
  double normalize(double value) {
    final clamped = value.clamp(min, max).toDouble();
    final step = this.step;
    if (step == null) return clamped;
    final steps = ((clamped - min) / step).round();
    return math.min(max, min + steps * step);
  }

  bool contains(double value) => value >= min && value <= max;

  /// Whether the range collapses to a single value, i.e. the capability is
  /// readable but not adjustable.
  bool get isFixed => min == max;

  @override
  bool operator ==(Object other) =>
      other is CapabilityRange &&
      other.min == min &&
      other.max == max &&
      other.step == step;

  @override
  int get hashCode => Object.hash(min, max, step);

  @override
  String toString() =>
      'CapabilityRange(min: $min, max: $max${step == null ? '' : ', step: $step'})';
}
