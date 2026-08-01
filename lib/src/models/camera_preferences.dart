import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_distance.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_mode.dart';

/// How the camera should be chosen and configured.
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
  })  : assert(idealWidth > 0 && idealHeight > 0, 'resolution must be positive'),
        assert(maxProbedCameras >= 0, 'maxProbedCameras cannot be negative'),
        assert(zoom == null || zoom >= 1.0, 'zoom below 1.0 is not meaningful');

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

  /// Defaults tuned for [mode].
  ///
  /// Linear barcodes are typically presented closer and need the horizontal
  /// resolution, so they get [ScanDistance.near]. QR codes tolerate distance
  /// and lower resolution well.
  factory CameraPreferences.forMode(ScanMode mode) => mode.isLinear
      ? const CameraPreferences(distance: ScanDistance.near)
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
    );
  }
}
