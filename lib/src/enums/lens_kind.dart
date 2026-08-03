/// The kind of lens a camera device represents.
///
/// Browsers expose each lens of a multi-camera phone as a separate video input
/// device, distinguishable only by its localised label. Classifying the lens is
/// what lets the selector reason about the close-focus / resolution trade-off
/// instead of guessing from raw strings.
enum LensKind {
  /// The primary wide lens. Best resolution on target, longest minimum focus
  /// distance on most phones.
  main,

  /// Ultra-wide lens. Focuses much closer but resolves less detail and adds
  /// barrel distortion at the frame edges.
  ultraWide,

  /// Telephoto lens. Longest minimum focus distance; almost never right for
  /// scanning.
  telephoto,

  /// Dedicated macro lens, where the device exposes one.
  macro,

  /// Depth, infrared or time-of-flight sensor. Cannot produce a decodable
  /// image and must never be selected.
  depth,

  /// Lens kind could not be determined from the available signals.
  unknown;

  /// Whether this lens can produce a usable image for decoding at all.
  bool get isUsable => this != LensKind.depth;
}
