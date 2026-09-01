/// Which way a camera points.
///
/// Sourced from `InputDeviceInfo.getCapabilities().facingMode` when the browser
/// exposes it (Chromium), and inferred from the device label otherwise
/// (Safari/Firefox). See [CameraSelector] for the inference rules.
enum CameraFacing {
  /// Selfie camera. Almost never what a scanner wants.
  front,

  /// Rear-facing camera. The default target for scanning.
  back,

  /// A camera the browser reports without a facing mode, typically an external
  /// USB webcam on desktop.
  external,

  /// Facing could not be determined.
  unknown;

  static CameraFacing fromConstraint(String? raw) => switch (raw?.trim()) {
    'user' => CameraFacing.front,
    'environment' => CameraFacing.back,
    'left' || 'right' => CameraFacing.external,
    _ => CameraFacing.unknown,
  };
}
