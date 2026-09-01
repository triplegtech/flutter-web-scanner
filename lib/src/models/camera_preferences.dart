import 'package:flutter_web_scanner/src/enums/scan_distance.dart';
import 'package:flutter_web_scanner/src/enums/scan_mode.dart';

/// How the camera should be chosen and configured, and how hard the decoder
/// should work on what it produces.
class CameraPreferences {
  const CameraPreferences({
    this.distance = ScanDistance.auto,
    this.idealWidth = 1920,
    this.idealHeight = 1080,
    this.idealFrameRate = 30,
    this.probeCapabilities = true,
    this.maxProbedCameras = 3,
    this.continuousFocus = true,
    this.zoom,
    this.torch = false,
    this.decodeInterval = const Duration(milliseconds: 100),
    this.roiWidthFactor = 1.0,
    this.roiHeightFactor = 1.0,
    this.tryHarder = true,
  }) : assert(idealWidth > 0 && idealHeight > 0, 'resolution must be positive'),
       assert(maxProbedCameras >= 0, 'maxProbedCameras cannot be negative'),
       assert(zoom == null || zoom >= 1.0, 'zoom below 1.0 is not meaningful'),
       assert(
         roiWidthFactor > 0 && roiWidthFactor <= 1,
         'roiWidthFactor must be within (0, 1]',
       ),
       assert(
         roiHeightFactor > 0 && roiHeightFactor <= 1,
         'roiHeightFactor must be within (0, 1]',
       );

  /// Expected distance between lens and code. See [ScanDistance].
  final ScanDistance distance;

  /// Preferred capture width in pixels, requested as `ideal`.
  ///
  /// This matters more than anything else for 1D barcodes. Without an explicit
  /// request browsers hand back 640x480, at which the bar/space pattern of an
  /// EAN-13 held at arm's length lands on too few pixels to decode. `ideal`
  /// (not `exact`) means a device that cannot deliver it still starts, just at
  /// its best available size.
  final int idealWidth;

  /// Preferred capture height in pixels, requested as `ideal`.
  final int idealHeight;

  /// Preferred frame rate. Higher rates give the stabiliser more chances to
  /// confirm a read per second.
  final int idealFrameRate;

  /// Briefly open candidate cameras to read their real capabilities before
  /// committing to one.
  ///
  /// `MediaStreamTrack.getCapabilities()` is the only way to learn a lens's
  /// minimum focus distance, and it needs a live track. Probing costs roughly
  /// 200-400 ms per camera on first run, after which the choice is far better
  /// than any label guess. Disable it when startup latency matters more than
  /// close-range accuracy.
  final bool probeCapabilities;

  /// Upper bound on how many cameras get probed, so a device exposing six
  /// lenses does not add seconds to startup.
  final int maxProbedCameras;

  /// Request `focusMode: continuous` once the track is live.
  ///
  /// Without it many Android devices keep a fixed focus set for distant
  /// subjects and never sharpen on a code held close.
  final bool continuousFocus;

  /// Fixed digital zoom factor, or `null` to let the package pick one.
  ///
  /// Automatic zoom exists to recover detail lost when a wide or ultra-wide
  /// lens is chosen for its close focus: zooming crops toward the centre of the
  /// frame, which is exactly where the overlay tells the user to put the code.
  final double? zoom;

  /// Turn the torch on when the device supports it.
  final bool torch;

  /// Idle gap left between decode attempts.
  ///
  /// A negative duration is treated as zero rather than rejected: `Duration`
  /// cannot be compared inside a `const` assert, so the check happens where
  /// the value crosses into the interop layer.
  ///
  /// This is a gap, not a period: a frame that takes 40 ms to decode with a
  /// 100 ms interval occupies roughly a third of the main thread, leaving the
  /// rest to Flutter. It is the knob that decides whether the page stays
  /// responsive, because decoding runs on the same thread as rendering.
  ///
  /// Shortening it costs battery and frame budget for a little less latency
  /// before a code is confirmed; at the default a `ScanValidation` gets ten
  /// attempts per second, far more than the two confirmations it asks for
  /// within its window.
  final Duration decodeInterval;

  /// Width of the decoded region, as a fraction of the visible preview.
  ///
  /// The preview is rendered with `object-fit: cover`, so part of each frame
  /// falls outside the widget and can never be aimed at. That part is always
  /// discarded — `1.0` means "everything the user can see", not "the whole
  /// sensor frame". On a portrait phone showing a landscape stream this alone
  /// removes roughly two thirds of every frame.
  ///
  /// Lower it to match a tighter overlay: the region is centred, so `0.8`
  /// decodes the middle 80% of the visible width and ignores codes at the
  /// edges. The region is cropped, never scaled, so the pixel density that
  /// [idealWidth] buys is preserved.
  final double roiWidthFactor;

  /// Height of the decoded region, as a fraction of the visible preview.
  ///
  /// See [roiWidthFactor]. Pairs well with the wide, short cut-out that
  /// [ScanMode.barcode] draws — a linear symbol only ever occupies a band
  /// across the middle of the frame.
  final double roiHeightFactor;

  /// Ask the decoder to work harder on each frame.
  ///
  /// Cheap on 2D codes, which are found by a single-pass detector, and brutal
  /// on 1D ones: ZXing's `OneDReader` scans 15 rows spread across the middle
  /// of the region without it and *every* row of the region with it, then
  /// repeats the whole search on a rotated copy — for each enabled symbology.
  /// On a 1080-tall region that is the difference between fifteen row scans
  /// and well over two thousand, on the same thread that renders the page.
  ///
  /// Hence [CameraPreferences.forMode] leaves it on for [ScanMode.qrCode] and
  /// turns it off for [ScanMode.barcode]. What it buys is a read of a blurred
  /// or tilted symbol on an attempt that would otherwise miss; on a live
  /// camera the next attempt is 100 ms away, so a miss costs latency rather
  /// than accuracy.
  ///
  /// Has no effect on the native `BarcodeDetector` engine, which exposes no
  /// equivalent, or on still-image decoding, where one attempt is all there is
  /// and it stays on regardless.
  final bool tryHarder;

  /// Defaults tuned for [mode].
  ///
  /// Linear barcodes are typically presented closer and need the horizontal
  /// resolution, so they get [ScanDistance.near]. QR codes tolerate distance
  /// and lower resolution well.
  factory CameraPreferences.forMode(ScanMode mode) => mode.isLinear
      ? const CameraPreferences(
          distance: ScanDistance.near,
          // A linear symbol is a horizontal band, and the overlay this mode
          // draws is a short wide window telling the user exactly that. Reading
          // only that band halves the pixels every attempt has to grayscale,
          // binarise and scan. Chosen to still contain the whole drawn window,
          // which sits slightly above centre — a code framed where the user was
          // told to frame it must never fall outside what is decoded.
          roiHeightFactor: 0.5,
          // The rest of the frame's width is where a barcode too long for the
          // window still is, so this stays whole.
          roiWidthFactor: 1.0,
          // ZXing's 1D path is the reason barcode mode used to stall the page.
          // With TRY_HARDER it scans *every* row of the region rather than 15
          // spread across the middle — 1080 passes instead of 15 on a 1080-tall
          // region — and then repeats the whole thing on a rotated copy, once
          // per enabled symbology. That is affordable for a single still image
          // and ruinous ten times a second on the thread that also renders the
          // page. Fifteen rows across a band the user is actively aiming is
          // plenty, and a miss costs one frame out of ten rather than accuracy.
          tryHarder: false,
        )
      : const CameraPreferences();

  CameraPreferences copyWith({
    ScanDistance? distance,
    int? idealWidth,
    int? idealHeight,
    int? idealFrameRate,
    bool? probeCapabilities,
    int? maxProbedCameras,
    bool? continuousFocus,
    double? zoom,
    bool? torch,
    Duration? decodeInterval,
    double? roiWidthFactor,
    double? roiHeightFactor,
    bool? tryHarder,
  }) {
    return CameraPreferences(
      distance: distance ?? this.distance,
      idealWidth: idealWidth ?? this.idealWidth,
      idealHeight: idealHeight ?? this.idealHeight,
      idealFrameRate: idealFrameRate ?? this.idealFrameRate,
      probeCapabilities: probeCapabilities ?? this.probeCapabilities,
      maxProbedCameras: maxProbedCameras ?? this.maxProbedCameras,
      continuousFocus: continuousFocus ?? this.continuousFocus,
      zoom: zoom ?? this.zoom,
      torch: torch ?? this.torch,
      decodeInterval: decodeInterval ?? this.decodeInterval,
      roiWidthFactor: roiWidthFactor ?? this.roiWidthFactor,
      roiHeightFactor: roiHeightFactor ?? this.roiHeightFactor,
      tryHarder: tryHarder ?? this.tryHarder,
    );
  }

  // WebScanner compares the preferences it was given against the previous
  // ones to decide whether the camera has to be reopened. Without this that
  // comparison is by identity, and `cameraPreferences: CameraPreferences()`
  // written inside a build method — a fresh instance every rebuild — tears the
  // session down and back up on each one, which reads as a scanner that has
  // simply stopped decoding.
  @override
  bool operator ==(Object other) =>
      other is CameraPreferences &&
      other.distance == distance &&
      other.idealWidth == idealWidth &&
      other.idealHeight == idealHeight &&
      other.idealFrameRate == idealFrameRate &&
      other.probeCapabilities == probeCapabilities &&
      other.maxProbedCameras == maxProbedCameras &&
      other.continuousFocus == continuousFocus &&
      other.zoom == zoom &&
      other.torch == torch &&
      other.decodeInterval == decodeInterval &&
      other.roiWidthFactor == roiWidthFactor &&
      other.roiHeightFactor == roiHeightFactor &&
      other.tryHarder == tryHarder;

  @override
  int get hashCode => Object.hash(
    distance,
    idealWidth,
    idealHeight,
    idealFrameRate,
    probeCapabilities,
    maxProbedCameras,
    continuousFocus,
    zoom,
    torch,
    decodeInterval,
    roiWidthFactor,
    roiHeightFactor,
    tryHarder,
  );
}
