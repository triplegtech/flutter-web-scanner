/// Which decoding engine backs the scanner.
enum ScanEngine {
  /// Use the browser's native `BarcodeDetector` when it is available and
  /// supports the requested formats, otherwise fall back to [zxing].
  ///
  /// This is the best default for new apps: native decoding runs outside the
  /// JS main thread and is markedly better on blurred or close-range 1D codes,
  /// while the fallback keeps Safari and Firefox working.
  auto,

  /// Always use `@zxing/library`.
  ///
  /// Requires the ZXing UMD bundle to be present on `window`. This is the
  /// default so that apps upgrading from 1.x keep their existing
  /// `index.html` setup working unchanged.
  zxing,

  /// Always use the native `BarcodeDetector` API.
  ///
  /// Fails fast with a clear error when the browser does not implement it, so
  /// only pick this when the deployment target is known to support it.
  native;

  /// Whether the ZXing UMD bundle must be present on `window` for this choice
  /// to work.
  ///
  /// [auto] still needs it, since it is the fallback path.
  bool get requiresZXing => this != ScanEngine.native;
}
