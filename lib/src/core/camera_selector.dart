import 'package:omni_qrcode_barcode_web_reader/src/enums/camera_facing.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/lens_kind.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_distance.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_mode.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_model.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_preferences.dart';

/// A camera with its computed suitability score.
class CameraCandidate {
  const CameraCandidate({
    required this.camera,
    required this.score,
    required this.lens,
    required this.facing,
    this.reasons = const <String>[],
  });

  final CameraModel camera;

  /// Higher is better. Scores are only meaningful relative to each other
  /// within a single [CameraSelector.rank] call.
  final double score;

  final LensKind lens;
  final CameraFacing facing;

  /// Human-readable breakdown of what drove the score.
  ///
  /// Exists because this heuristic can only be debugged against real hardware,
  /// and a browser console on someone else's phone is the only instrument
  /// available.
  final List<String> reasons;

  @override
  String toString() {
    final name = camera.hasLabel ? camera.label : camera.deviceId;
    return 'CameraCandidate($name, score: ${score.toStringAsFixed(1)}, '
        'lens: ${lens.name}, facing: ${facing.name})';
  }
}

/// Ranks camera devices by how well they suit a given scanning task.
///
/// Pure and deterministic: the same inputs always produce the same ordering,
/// with no browser calls. That is what makes this — the part most likely to
/// regress — fully unit-testable.
///
/// The ranking blends three signal tiers, in descending order of trust:
///
/// 1. **Live capabilities** ([CameraCapabilities.focusDistance], frame size).
///    Measured facts. Dominates when present.
/// 2. **Reported facing mode** from `InputDeviceInfo.getCapabilities()`.
///    Authoritative but Chromium-only.
/// 3. **Label keywords**. A last resort: labels are localised, vendor-specific
///    and empty before permission is granted.
abstract final class CameraSelector {
  /// Reference frame size used to normalise resolution scoring.
  static const int _referencePixels = 1920 * 1080;

  /// Beyond this minimum focus distance (metres) a lens is treated as unable
  /// to focus on a code held close to it.
  static const double _closeFocusCeiling = 0.15;

  static const Map<CameraFacing, List<String>> _facingKeywords = {
    CameraFacing.front: [
      'front', 'frontal', 'user', 'selfie', 'facetime', //
      'usuário', 'usuario', 'delantera', 'avant', 'vorne', //
      'anteriore', 'voorkant',
    ],
    CameraFacing.back: [
      'back', 'rear', 'environment', 'world', //
      'traseira', 'trasera', 'ambiente', 'arrière', 'arriere', //
      'rück', 'ruck', 'rueck', 'hinten', 'posteriore', 'achterkant',
    ],
  };

  static const Map<LensKind, List<String>> _lensKeywords = {
    // Ordered most-specific first: 'ultra wide' must win over 'wide', and
    // 'truedepth' over 'depth', so matching walks this map in order.
    LensKind.depth: [
      'truedepth', 'depth', 'infrared', 'ir camera', 'tof', //
      'profundidade', 'profundidad', 'profondeur', 'tiefe',
    ],
    LensKind.ultraWide: [
      'ultra wide', 'ultra-wide', 'ultrawide', 'ultra angular', //
      'ultra-angular', 'grande angular', 'gran angular', //
      'ultra grand angle', 'ultraweitwinkel', 'grandangolo', //
      'super wide', 'super-wide',
    ],
    LensKind.macro: ['macro', 'makro'],
    LensKind.telephoto: [
      'telephoto', 'tele', 'teleobjetiva', 'teleobjetivo', //
      'téléobjectif', 'teleobjectif', 'teleobjektiv', 'zoom',
    ],
    LensKind.main: [
      'wide', 'angular', 'grand angle', 'weitwinkel', 'main', //
      'principal', 'haupt',
    ],
  };

  /// Ranks [cameras] best-first for the given task.
  ///
  /// Never returns fewer entries than it was given: unsuitable cameras sink to
  /// the bottom rather than being dropped. This is deliberate — a device whose
  /// only camera is front-facing (laptops, some tablets) must still be able to
  /// scan, and silently returning an empty list is what previously surfaced as
  /// a spurious "no camera found" error.
  static List<CameraCandidate> rank(
    List<CameraModel> cameras, {
    required ScanMode mode,
    required CameraPreferences preferences,
  }) {
    final candidates = <CameraCandidate>[
      for (final camera in cameras)
        _score(camera, mode: mode, preferences: preferences),
    ];

    // Sort by score descending, falling back to enumeration order so the
    // result is stable for cameras the heuristics cannot separate.
    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.camera.order.compareTo(b.camera.order);
    });
    return candidates;
  }

  /// Returns the cameras worth spending a capability probe on.
  ///
  /// Probing opens a real stream, so it is capped by
  /// [CameraPreferences.maxProbedCameras] and skips cameras already carrying
  /// focus data or known to be unusable.
  static List<CameraModel> probeTargets(
    List<CameraCandidate> ranked,
    CameraPreferences preferences,
  ) {
    if (!preferences.probeCapabilities || preferences.maxProbedCameras == 0) {
      return const <CameraModel>[];
    }
    final worthProbing = ranked
        .where((c) => c.lens.isUsable)
        .where((c) => c.facing != CameraFacing.front)
        .where((c) => c.camera.capabilities.focusDistance == null)
        .where((c) => c.camera.deviceId.isNotEmpty)
        .map((c) => c.camera)
        .toList();
    if (worthProbing.length <= preferences.maxProbedCameras) {
      return worthProbing;
    }
    return worthProbing.sublist(0, preferences.maxProbedCameras);
  }

  static CameraCandidate _score(
    CameraModel camera, {
    required ScanMode mode,
    required CameraPreferences preferences,
  }) {
    final reasons = <String>[];
    final capabilities = camera.capabilities;

    final facing = capabilities.facing != CameraFacing.unknown
        ? capabilities.facing
        : inferFacing(camera.label);
    final lens = inferLens(camera.label);

    var score = 0.0;

    score += switch (facing) {
      CameraFacing.back => _add(reasons, 'rear-facing', 1000),
      CameraFacing.front => _add(reasons, 'front-facing', -1000),
      CameraFacing.external => _add(reasons, 'external camera', -100),
      CameraFacing.unknown => 0.0,
    };

    if (!lens.isUsable) {
      score += _add(reasons, 'depth/IR sensor cannot decode', -5000);
    } else {
      score += _lensScore(lens, preferences.distance, reasons);
    }

    score += _focusScore(camera, preferences.distance, reasons);
    score += _resolutionScore(camera, mode, reasons);

    if (capabilities.supportsContinuousFocus) {
      score += _add(reasons, 'supports continuous focus', 50);
    }
    final zoom = capabilities.zoom;
    if (zoom != null && !zoom.isFixed) {
      score += _add(reasons, 'adjustable zoom available', 25);
    }
    if (!camera.hasLabel && capabilities.facing == CameraFacing.unknown) {
      // Nothing at all is known about this device. Keep it selectable but
      // behind anything we could actually reason about.
      score += _add(reasons, 'no label and no capabilities', -25);
    }

    // Deterministic tie-break: browsers tend to list the default camera first.
    score -= camera.order * 0.1;

    return CameraCandidate(
      camera: camera,
      score: score,
      lens: lens,
      facing: facing,
      reasons: reasons,
    );
  }

  static double _lensScore(
    LensKind lens,
    ScanDistance distance,
    List<String> reasons,
  ) {
    final points = switch ((distance, lens)) {
      // Close range: short minimum focus beats pixels on target.
      (ScanDistance.near, LensKind.macro) => 350,
      (ScanDistance.near, LensKind.ultraWide) => 300,
      (ScanDistance.near, LensKind.main) => 100,
      (ScanDistance.near, LensKind.telephoto) => -150,

      // Normal range: the main lens puts the most detail on the target, and
      // ultra-wide distortion actively hurts 1D decoding.
      (ScanDistance.normal, LensKind.main) => 300,
      (ScanDistance.normal, LensKind.macro) => 0,
      (ScanDistance.normal, LensKind.ultraWide) => -50,
      (ScanDistance.normal, LensKind.telephoto) => 50,

      // Auto: prefer the main lens, but leave macro-capable lenses close
      // enough behind that measured focus data can overturn the choice.
      (ScanDistance.auto, LensKind.main) => 250,
      (ScanDistance.auto, LensKind.macro) => 100,
      (ScanDistance.auto, LensKind.ultraWide) => 50,
      (ScanDistance.auto, LensKind.telephoto) => -50,
      (_, LensKind.unknown) => 0,
      (_, LensKind.depth) => 0,
    };
    if (points != 0) {
      _add(reasons, '${lens.name} lens at ${distance.name} range', points);
    }
    return points.toDouble();
  }

  /// Scores measured minimum focus distance, the strongest available signal
  /// for close-range work.
  static double _focusScore(
    CameraModel camera,
    ScanDistance distance,
    List<String> reasons,
  ) {
    final focus = camera.capabilities.focusDistance;
    if (focus == null) return 0;

    final closest = focus.min;
    return switch (distance) {
      // Reward getting closer, linearly, up to a 20 cm ceiling.
      ScanDistance.near => _add(
          reasons,
          'focuses as close as ${(closest * 100).toStringAsFixed(1)} cm',
          (((0.20 - closest) / 0.20).clamp(0.0, 1.0) * 400).round(),
        ),
      // Mild reward, since at arm's length nearly any lens can focus.
      ScanDistance.normal => _add(
          reasons,
          'minimum focus ${(closest * 100).toStringAsFixed(1)} cm',
          (((0.30 - closest) / 0.30).clamp(0.0, 1.0) * 80).round(),
        ),
      // Penalise only lenses that genuinely cannot focus up close. This is the
      // rule that lets a measured macro lens overtake the main lens.
      ScanDistance.auto => closest > _closeFocusCeiling
          ? _add(
              reasons,
              'cannot focus closer than '
              '${(closest * 100).toStringAsFixed(1)} cm',
              -200,
            )
          : _add(
              reasons,
              'focuses close enough for short range',
              150,
            ),
    };
  }

  static double _resolutionScore(
    CameraModel camera,
    ScanMode mode,
    List<String> reasons,
  ) {
    final pixels = camera.capabilities.maxPixels;
    if (pixels == null) return 0;

    // 1D symbols depend on horizontal sampling of thin bars, so resolution
    // carries more weight for them than for error-corrected 2D symbols.
    final weight = mode.isLinear ? 120 : 70;
    final normalized = (pixels / _referencePixels).clamp(0.0, 2.0);
    return _add(
      reasons,
      'delivers up to ${camera.capabilities.maxWidth}'
      'x${camera.capabilities.maxHeight}',
      (normalized * weight).round(),
    );
  }

  /// Infers which way a camera points from its label.
  ///
  /// Only used when the browser does not report `facingMode`.
  static CameraFacing inferFacing(String label) {
    final normalized = _normalize(label);
    if (normalized.isEmpty) return CameraFacing.unknown;
    for (final entry in _facingKeywords.entries) {
      if (entry.value.any(normalized.contains)) return entry.key;
    }
    return CameraFacing.unknown;
  }

  /// Infers the lens kind from a camera label.
  static LensKind inferLens(String label) {
    final normalized = _normalize(label);
    if (normalized.isEmpty) return LensKind.unknown;
    // _lensKeywords is ordered most-specific first so that, for example,
    // "Back Ultra Wide Camera" resolves to ultraWide rather than main.
    for (final entry in _lensKeywords.entries) {
      if (entry.value.any(normalized.contains)) return entry.key;
    }
    return LensKind.unknown;
  }

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Lowercases and collapses whitespace so keyword matching is not defeated
  /// by vendor spacing quirks.
  static String _normalize(String label) =>
      label.toLowerCase().replaceAll(_whitespace, ' ').trim();

  /// Records [points] against [reason] and returns it, so scoring stays a
  /// single readable expression.
  static double _add(List<String> reasons, String reason, int points) {
    if (points != 0) {
      reasons.add('${points > 0 ? '+' : ''}$points $reason');
    }
    return points.toDouble();
  }
}
