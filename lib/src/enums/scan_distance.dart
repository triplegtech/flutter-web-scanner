/// How far the code being scanned is expected to be from the lens.
///
/// This exists because multi-lens phones force a real trade-off that no single
/// camera wins outright:
///
/// * The **main (wide)** lens has the largest sensor and puts the most pixels
///   on the target, but on most phones it cannot focus closer than ~10 cm.
/// * The **ultra-wide** lens focuses much closer (it is what powers "macro"
///   mode on recent iPhones) but resolves the target with fewer pixels and adds
///   barrel distortion at the edges, which specifically hurts 1D barcodes.
///
/// Rather than hard-coding one lens per platform, the caller states the
/// distance and [CameraSelector] weighs the trade-off with real capability data
/// when the browser exposes it.
enum ScanDistance {
  /// Code held very close to the lens (roughly under 10 cm).
  ///
  /// Prioritises the smallest reachable minimum focus distance and compensates
  /// for the weaker lens with digital zoom.
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
