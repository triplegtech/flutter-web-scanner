import 'package:flutter_web_scanner/src/enums/camera_facing.dart';
import 'package:flutter_web_scanner/src/models/capability_range.dart';

/// What a camera can actually do, as reported by the browser.
///
/// Two different APIs feed this, with very different reliability:
///
/// * `InputDeviceInfo.getCapabilities()` on the enumerated device — available
///   before opening a stream, but Chromium-only and limited to [facing] and
///   frame size.
/// * `MediaStreamTrack.getCapabilities()` on a live track — the authoritative
///   source for [focusDistance], [zoom] and [focusModes], but only obtainable
///   by actually opening the camera.
///
/// Every field is nullable because no browser reports all of them, and the
/// selection logic is written to degrade rather than assume.
class CameraCapabilities {
  const CameraCapabilities({
    this.facing = CameraFacing.unknown,
    this.focusDistance,
    this.zoom,
    this.maxWidth,
    this.maxHeight,
    this.focusModes = const <String>[],
    this.supportsTorch = false,
  });

  static const CameraCapabilities unknown = CameraCapabilities();

  /// Direction the lens points, when the browser reports `facingMode`.
  final CameraFacing facing;

  /// Focus distance range **in metres**. `focusDistance.min` is the closest the
  /// lens can focus and is the single most predictive signal for close-range
  /// scanning.
  final CapabilityRange? focusDistance;

  /// Digital zoom factor range, where `1.0` means no zoom.
  final CapabilityRange? zoom;

  /// Largest frame width the device can deliver, in pixels.
  final int? maxWidth;

  /// Largest frame height the device can deliver, in pixels.
  final int? maxHeight;

  /// Supported `focusMode` values, e.g. `manual`, `single-shot`, `continuous`.
  final List<String> focusModes;

  /// Whether the track exposes a torch/flash toggle.
  final bool supportsTorch;

  bool get supportsContinuousFocus => focusModes.contains('continuous');

  /// Total pixels the sensor can deliver, used to compare how much detail a
  /// lens can put on the target. `null` when frame size is unknown.
  int? get maxPixels => switch ((maxWidth, maxHeight)) {
    (final int width, final int height) => width * height,
    _ => null,
  };

  /// Whether the lens can focus closer than [metres].
  ///
  /// Returns `null` — not `false` — when focus distance is unknown, so callers
  /// can distinguish "cannot do it" from "we do not know".
  bool? canFocusCloserThan(double metres) {
    final focus = focusDistance;
    if (focus == null) return null;
    return focus.min <= metres;
  }

  CameraCapabilities copyWith({
    CameraFacing? facing,
    CapabilityRange? focusDistance,
    CapabilityRange? zoom,
    int? maxWidth,
    int? maxHeight,
    List<String>? focusModes,
    bool? supportsTorch,
  }) {
    return CameraCapabilities(
      facing: facing ?? this.facing,
      focusDistance: focusDistance ?? this.focusDistance,
      zoom: zoom ?? this.zoom,
      maxWidth: maxWidth ?? this.maxWidth,
      maxHeight: maxHeight ?? this.maxHeight,
      focusModes: focusModes ?? this.focusModes,
      supportsTorch: supportsTorch ?? this.supportsTorch,
    );
  }

  /// Overlays [other] on top of this, preferring non-null values from [other].
  ///
  /// Used to fold authoritative live-track capabilities into the coarser
  /// enumeration-time ones without losing what only the latter knew.
  CameraCapabilities mergeWith(CameraCapabilities other) {
    return CameraCapabilities(
      facing: other.facing != CameraFacing.unknown ? other.facing : facing,
      focusDistance: other.focusDistance ?? focusDistance,
      zoom: other.zoom ?? zoom,
      maxWidth: other.maxWidth ?? maxWidth,
      maxHeight: other.maxHeight ?? maxHeight,
      focusModes: other.focusModes.isNotEmpty ? other.focusModes : focusModes,
      supportsTorch: other.supportsTorch || supportsTorch,
    );
  }

  @override
  String toString() =>
      'CameraCapabilities(facing: ${facing.name}, '
      'focusDistance: $focusDistance, zoom: $zoom, '
      'max: ${maxWidth}x$maxHeight, torch: $supportsTorch)';
}
