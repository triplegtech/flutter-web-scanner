import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_web_scanner/src/controllers/scanner_state.dart';
import 'package:flutter_web_scanner/src/core/camera_selector.dart';
import 'package:flutter_web_scanner/src/core/detection_stabilizer.dart';
import 'package:flutter_web_scanner/src/enums/scan_engine.dart';
import 'package:flutter_web_scanner/src/enums/scan_mode.dart';
import 'package:flutter_web_scanner/src/models/barcode_result.dart';
import 'package:flutter_web_scanner/src/models/camera_model.dart';
import 'package:flutter_web_scanner/src/models/camera_preferences.dart';
import 'package:flutter_web_scanner/src/models/scan_rejection.dart';
import 'package:flutter_web_scanner/src/models/scan_validation.dart';
import 'package:flutter_web_scanner/src/models/scanner_failure.dart';
import 'package:flutter_web_scanner/src/platform/scanner_platform.dart';

/// Owns the scanner's lifecycle: camera choice, session start/stop, and the
/// validation pipeline between a raw decode and `onDetect`.
///
/// Deliberately holds no `BuildContext` and imports nothing browser-specific,
/// so its entire flow — including failure paths that are impractical to
/// reproduce on real hardware — is exercisable with a fake [ScannerPlatform].
class ScannerController extends ChangeNotifier {
  ScannerController({
    required this.onDetect,
    this.onFailure,
    this.onReject,
    this.onRawDecode,
    this.mode = ScanMode.barcode,
    this.engine = ScanEngine.zxing,
    ScanValidation? validation,
    CameraPreferences? preferences,
    ScannerPlatform? platform,
    DateTime Function()? clock,
    String? instanceId,
  }) : preferences = preferences ?? CameraPreferences.forMode(mode),
       _platform = platform ?? ScannerPlatformResolver.instance,
       // Bare counter: [viewId] and [containerId] add the prefix themselves,
       // and a prefix here too would name every element twice over.
       id = instanceId ?? '${_instanceCounter++}' {
    _stabilizer = DetectionStabilizer(
      validation: validation ?? ScanValidation.forMode(mode),
      clock: clock,
    );
    _platform.registerView(viewId: viewId, containerId: containerId);
  }

  /// Monotonic per-isolate counter.
  ///
  /// Preferred over a timestamp so ids stay reproducible in tests and two
  /// scanners created in the same microsecond cannot collide.
  static int _instanceCounter = 0;

  /// Unique identifier for this scanner instance.
  final String id;

  final void Function(BarcodeResult result) onDetect;
  final void Function(ScannerFailure failure)? onFailure;

  /// Called for each decode that validation discarded.
  ///
  /// Fires many times per second during normal aiming, so it is opt-in and
  /// meant for diagnosing a scanner that decodes but never emits — the failure
  /// mode `validation` introduces and the only one that raises no
  /// [ScannerFailure]. Leave it null in production.
  final void Function(ScanRejection rejection)? onReject;

  /// Called with every decode the engine produced, untouched.
  ///
  /// The counterpart to [onDetect], and deliberately everything [onDetect] is
  /// not: no checksum check, no format filter, no confirmation streak and no
  /// cooldown. A code left in frame therefore arrives once per decoded frame,
  /// and a misread arrives next to the good reads rather than instead of them.
  ///
  /// That is the point — it is the only view of what the engine actually
  /// returned, which is what a caller needs to tune [validation], to log a
  /// payload the rules are wrongly rejecting, or to apply a policy this
  /// package does not model. [RawDecode.rawFormat] carries the symbology name
  /// exactly as the engine spelled it, before [BarcodeFormat.parse] normalises
  /// it.
  ///
  /// Runs on the decode path at up to tens of calls per second, so keep it
  /// cheap: an unconditional `setState` here rebuilds the tree that often.
  final void Function(RawDecode decode)? onRawDecode;

  final ScanMode mode;
  final ScanEngine engine;
  final CameraPreferences preferences;

  /// Rules a raw decode must pass before reaching [onDetect].
  ///
  /// Unlike [mode], [engine] and [preferences], this is not baked into the
  /// camera session: it is applied downstream of the decoder, so it can be
  /// replaced on a live scanner without reopening the stream. That matters for
  /// [ScanValidation.guard] in particular — a closure written inside a build
  /// method is a new object on every rebuild, and making that reopen the camera
  /// would blank the preview after every read.
  ///
  /// The confirmation streak and cooldowns survive the swap, so new rules
  /// cannot resurface a code that was just emitted.
  ScanValidation get validation => _stabilizer.validation;
  set validation(ScanValidation value) => _stabilizer.validation = value;

  final ScannerPlatform _platform;
  late final DetectionStabilizer _stabilizer;

  String get viewId => 'flutter-web-scanner-view-$id';
  String get containerId => 'flutter-web-scanner-container-$id';

  ScannerState _state = const ScannerIdle();
  ScannerState get state => _state;

  /// Cameras found during the last [start], best-first.
  List<CameraCandidate> get candidates => List.unmodifiable(_candidates);
  List<CameraCandidate> _candidates = const <CameraCandidate>[];

  bool _disposed = false;

  /// Guards against a slow start finishing after a newer one began.
  int _startGeneration = 0;

  /// Widget hosting the video element.
  Widget buildPreview() => _platform.buildPreview(viewId);

  /// Brings the scanner up: initialise, choose a camera, open the stream.
  ///
  /// Safe to call repeatedly; a start already in flight is superseded.
  Future<void> start() async {
    if (_disposed) return;

    final generation = ++_startGeneration;
    _setState(const ScannerInitializing());
    // A restart must not let a code read before it suppress the same code
    // read after it.
    _stabilizer.reset();

    try {
      final availability = await _platform.initialize();
      if (_isStale(generation)) return;

      // Fails fast with an actionable message rather than silently scanning
      // with an engine the caller did not ask for.
      final resolvedEngine = availability.resolve(engine);

      final camera = await _selectCamera(generation);
      if (_isStale(generation)) return;

      final session = await _platform.startSession(
        StartSessionRequest(
          sessionId: id,
          containerId: containerId,
          deviceId: camera?.deviceId,
          mode: mode,
          engine: resolvedEngine,
          preferences: preferences,
          onDecode: _handleDecode,
          onFailure: _handleFailure,
        ),
      );
      if (_isStale(generation)) {
        // A newer start won the race while this session was opening; release
        // its camera instead of leaking the track.
        await _platform.stopSession(session.id);
        return;
      }

      _setState(ScannerReady(session));
    } on ScannerFailure catch (failure) {
      if (_isStale(generation)) return;
      _reportFailure(failure);
    } on Object catch (error, stackTrace) {
      if (_isStale(generation)) return;
      // Interop and asset loading can surface arbitrary values, so anything
      // unclassified is normalised rather than escaping as an unhandled error.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'flutter_web_scanner',
          context: ErrorDescription('while starting the scanner'),
        ),
      );
      _reportFailure(
        ScannerFailure(
          ScannerFailureKind.startFailed,
          error.toString(),
          cause: error,
        ),
      );
    }
  }

  /// Stops the current session and starts a new one.
  Future<void> restart() async {
    await stop();
    await start();
  }

  /// Stops the session and releases the camera, leaving the controller usable.
  Future<void> stop() async {
    _startGeneration++;
    await _platform.stopSession(id);
    if (_disposed) return;
    _setState(const ScannerIdle());
  }

  /// Chooses the camera to open.
  ///
  /// Returns `null` when no camera can be identified, which is not an error:
  /// the JS constraint ladder falls back to `facingMode: environment` and then
  /// to any camera at all, so scanning still starts.
  Future<CameraModel?> _selectCamera(int generation) async {
    final cameras = await _platform.listCameras();
    if (_isStale(generation)) return null;
    if (cameras.isEmpty) {
      throw const ScannerFailure(
        ScannerFailureKind.noCameraFound,
        'the browser reported no video input devices',
      );
    }

    var ranked = CameraSelector.rank(
      cameras,
      mode: mode,
      preferences: preferences,
    );

    final refined = await _probeCandidates(ranked, generation);
    if (_isStale(generation)) return null;
    if (refined.isNotEmpty) {
      // Re-rank with measured focus distances, which outweigh every
      // label-derived guess and can legitimately overturn the initial order.
      ranked = CameraSelector.rank(
        refined,
        mode: mode,
        preferences: preferences,
      );
    }

    _candidates = ranked;
    return ranked.isEmpty ? null : ranked.first.camera;
  }

  /// Measures real capabilities for the top candidates.
  ///
  /// Returns the full camera list with any measurements folded in, or an empty
  /// list when nothing was probed. Failures are absorbed: probing is an
  /// optimisation and must never stop the scanner from starting.
  Future<List<CameraModel>> _probeCandidates(
    List<CameraCandidate> ranked,
    int generation,
  ) async {
    final targets = CameraSelector.probeTargets(ranked, preferences);
    if (targets.isEmpty) return const <CameraModel>[];

    final measured = <String, CameraModel>{
      for (final candidate in ranked)
        candidate.camera.deviceId: candidate.camera,
    };

    for (final target in targets) {
      if (_isStale(generation)) return const <CameraModel>[];
      final capabilities = await _platform.probeCamera(target.deviceId);
      if (capabilities == null) continue;
      final existing = measured[target.deviceId];
      if (existing == null) continue;
      measured[target.deviceId] = existing.withCapabilities(capabilities);
    }

    return measured.values.toList();
  }

  /// Runs a raw decode through validation and confirmation.
  void _handleDecode(RawDecode decode) {
    if (_disposed) return;

    // Handed over before the pipeline touches it, so a caller sees the same
    // reads the rules are about to judge — including the ones they discard.
    onRawDecode?.call(decode);

    final decision = _stabilizer.offer(decode.value, decode.format);
    switch (decision) {
      case StabilizerEmit(:final result):
        onDetect(result.copyWith(rawFormat: decode.rawFormat));
      case StabilizerRejected(:final rejection):
        onReject?.call(
          ScanRejection(
            value: decode.value,
            format: decode.format,
            rawFormat: decode.rawFormat,
            reason: rejection.reason,
            message: rejection.message,
          ),
        );
      case StabilizerPending():
      case StabilizerSuppressed():
        // Both are expected many times per second on the way to a good read,
        // and neither means anything is wrong.
        break;
    }
  }

  void _handleFailure(ScannerFailure failure) {
    if (_disposed) return;
    _reportFailure(failure);
  }

  void _reportFailure(ScannerFailure failure) {
    _setState(ScannerFailed(failure));
    onFailure?.call(failure);
  }

  /// Whether a newer [start] superseded generation [generation], or the
  /// controller was disposed while an await was pending.
  bool _isStale(int generation) => _disposed || generation != _startGeneration;

  void _setState(ScannerState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _startGeneration++;
    // Fire-and-forget: dispose cannot await, and the JS side releases tracks
    // defensively even if this races with teardown.
    unawaited(_platform.stopSession(id));
    super.dispose();
  }
}
