/// Classified reasons the scanner can fail.
///
/// Replaces the free-form error strings of 1.x. Callers need to branch on
/// *why* something failed — a denied permission wants a "grant access" prompt,
/// a camera already in use wants "close your other app", and a transient decode
/// hiccup wants no UI at all — and that decision cannot be made by pattern
/// matching on a localised sentence.
enum ScannerFailureKind {
  /// User denied camera access, or a Permissions Policy blocks it.
  permissionDenied,

  /// No video input device exists.
  noCameraFound,

  /// The camera is held by another application or tab.
  cameraInUse,

  /// The requested constraints cannot be satisfied by any device.
  overconstrained,

  /// The requested decoding engine is not available in this browser.
  engineUnavailable,

  /// Page is not in a secure context, so `getUserMedia` is unavailable.
  ///
  /// Camera access requires HTTPS or `localhost`; this is the failure people
  /// hit when testing from a LAN IP.
  insecureContext,

  /// Running somewhere other than Flutter Web.
  unsupportedPlatform,

  /// The camera was found and permitted but the stream failed to start.
  startFailed,

  /// Anything not otherwise classified.
  unknown;

  /// Whether retrying without user intervention could plausibly succeed.
  ///
  /// A denied permission or a missing engine will fail identically on retry, so
  /// offering a retry button for those is a dead end.
  bool get isRetryable => switch (this) {
        ScannerFailureKind.cameraInUse ||
        ScannerFailureKind.overconstrained ||
        ScannerFailureKind.startFailed ||
        ScannerFailureKind.unknown =>
          true,
        ScannerFailureKind.permissionDenied ||
        ScannerFailureKind.noCameraFound ||
        ScannerFailureKind.engineUnavailable ||
        ScannerFailureKind.insecureContext ||
        ScannerFailureKind.unsupportedPlatform =>
          false,
      };
}

/// A classified scanner error with technical detail preserved.
class ScannerFailure implements Exception {
  const ScannerFailure(this.kind, this.message, {this.cause});

  final ScannerFailureKind kind;

  /// Technical, non-localised description intended for logs and bug reports.
  ///
  /// User-facing copy comes from [ScannerLocalizations], keyed off [kind].
  final String message;

  /// Underlying error, when one exists.
  final Object? cause;

  bool get isRetryable => kind.isRetryable;

  /// Maps a `DOMException.name` from `getUserMedia` to a failure kind.
  ///
  /// Names come from the Media Capture spec; several are legacy aliases that
  /// older Safari and Firefox still emit, so all spellings are handled.
  static ScannerFailureKind kindFromDomError(String? name) =>
      switch (name?.trim()) {
        'NotAllowedError' ||
        'PermissionDeniedError' ||
        'SecurityError' =>
          ScannerFailureKind.permissionDenied,
        'NotFoundError' ||
        'DevicesNotFoundError' =>
          ScannerFailureKind.noCameraFound,
        'NotReadableError' ||
        'TrackStartError' ||
        'AbortError' =>
          ScannerFailureKind.cameraInUse,
        'OverconstrainedError' ||
        'ConstraintNotSatisfiedError' =>
          ScannerFailureKind.overconstrained,
        _ => ScannerFailureKind.unknown,
      };

  @override
  String toString() => 'ScannerFailure(${kind.name}: $message)';
}
