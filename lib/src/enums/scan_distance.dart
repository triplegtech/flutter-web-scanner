/// How far the code being scanned is expected to be from the lens.
///
/// This exists because multi-lens phones force a real trade-off that no single
/// camera wins outright:
///
/// * The **main (wide)** lens has the largest sensor, puts the most pixels on
///   the target, and is the one lens phones reliably give autofocus to. It
///   rarely focuses closer than ~10 cm, which is close enough for a code held
///   in front of it.
/// * The **ultra-wide** lens is widely assumed to be the close-focusing one,
///   because it is what powers "macro" on recent iPhones. That switch belongs
///   to the iOS camera app and does not happen through `getUserMedia`; on most
///   hardware the ultra-wide is fixed-focus, resolves the target with fewer
///   pixels, and adds barrel distortion that specifically hurts 1D barcodes.
///   Treat it as a close-focus lens only when the browser measures it as one.
///
/// Rather than hard-coding one lens per platform, the caller states the
/// distance and [CameraSelector] weighs the trade-off with real capability data
/// when the browser exposes it.
enum ScanDistance {
  /// Code held very close to the lens (roughly under 10 cm).
  ///
  /// Prioritises the smallest *measured* minimum focus distance. With nothing
  /// measured it stays on the main lens rather than betting on one whose label
  /// merely suggests it might focus closer.
  near,

  /// Code at a comfortable arm's length (roughly 15-40 cm).
  ///
  /// Prioritises the lens that puts the most pixels on the target.
  normal,

  /// Prefer the main lens, but switch to a macro-capable one when the main
  /// lens reports a minimum focus distance too long to be usable up close.
  ///
  /// Requires capability probing to make an informed choice; without it this
  /// behaves like [normal].
  auto;
}
