import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_web_scanner/flutter_web_scanner.dart';

/// In-memory [ScannerPlatform] used across the test suite.
///
/// Hand-written rather than generated: the interesting behaviour is the
/// *sequence* of interop calls and the callbacks they hand back, which a fake
/// expresses far more legibly than mock expectations. It also lets tests drive
/// failure paths — a camera already in use, a track ending mid-scan, an
/// overconstrained device — that cannot be reproduced on real hardware.
class FakeScannerPlatform implements ScannerPlatform {
  /// Key on the widget returned by [buildPreview].
  static const Key previewKey = Key('fake-scanner-preview');

  // --- Programmable responses ------------------------------------------------

  EngineAvailability availability = const EngineAvailability(
    zxingLoaded: true,
    nativeSupported: false,
    secureContext: true,
  );

  /// Thrown from [initialize] when set.
  Object? initializeError;

  List<CameraModel> cameras = <CameraModel>[
    const CameraModel(deviceId: 'back-1', label: 'Back Camera'),
  ];

  /// Thrown from [listCameras] when set.
  Object? listCamerasError;

  /// Capabilities returned by [probeCamera], keyed by device id.
  Map<String, CameraCapabilities> probeResults = <String, CameraCapabilities>{};

  /// Thrown from [startSession] when set.
  Object? startSessionError;

  /// When set, [startSession] parks until it completes.
  ///
  /// Lets a test hold one start mid-flight and begin a second, which is the
  /// only way to reach the controller's stale-session branch — on real hardware
  /// the race depends on how long the browser takes to hand back a track.
  Completer<void>? startSessionGate;

  /// Returned by [decodeImage].
  RawDecode? imageDecode;

  /// Thrown from [decodeImage] when set.
  Object? decodeImageError;

  // --- Recorded interactions -------------------------------------------------

  final List<StartSessionRequest> startRequests = <StartSessionRequest>[];

  /// MIME type, mode and engine of every [decodeImage] call.
  final List<({String mimeType, ScanMode mode, ScanEngine engine})>
  decodeRequests = <({String mimeType, ScanMode mode, ScanEngine engine})>[];

  final List<String> stoppedSessions = <String>[];
  final List<String> probedDeviceIds = <String>[];
  final List<String> registeredViewIds = <String>[];
  int initializeCount = 0;

  /// Device id passed to the most recent [startSession].
  String? get lastRequestedDeviceId =>
      startRequests.isEmpty ? null : startRequests.last.deviceId;

  // --- Session control -------------------------------------------------------

  void Function(RawDecode)? _onDecode;
  void Function(ScannerFailure)? _onFailure;

  /// Whether a session is currently open.
  bool get hasActiveSession => _onDecode != null;

  /// Simulates the decoder reporting a raw read.
  void emitDecode(String value, {String format = 'EAN_13'}) {
    _onDecode?.call(RawDecode(value: value, rawFormat: format));
  }

  /// Simulates a session-ending failure reported from the browser.
  void emitFailure(ScannerFailure failure) => _onFailure?.call(failure);

  // --- ScannerPlatform -------------------------------------------------------

  @override
  Future<EngineAvailability> initialize() async {
    initializeCount++;
    final error = initializeError;
    if (error != null) throw error;
    return availability;
  }

  @override
  Future<List<CameraModel>> listCameras() async {
    final error = listCamerasError;
    if (error != null) throw error;
    return cameras;
  }

  @override
  Future<CameraCapabilities?> probeCamera(String deviceId) async {
    probedDeviceIds.add(deviceId);
    return probeResults[deviceId];
  }

  @override
  Future<ScanSession> startSession(StartSessionRequest request) async {
    startRequests.add(request);
    // Captured before parking, so a test can retune the fake for a second
    // start without retroactively changing what this one does.
    final error = startSessionError;
    await startSessionGate?.future;
    if (error != null) throw error;

    _onDecode = request.onDecode;
    _onFailure = request.onFailure;

    final camera = cameras.isEmpty
        ? const CameraModel(deviceId: '', label: '')
        : cameras.firstWhere(
            (candidate) => candidate.deviceId == request.deviceId,
            orElse: () => cameras.first,
          );

    return ScanSession(
      id: request.sessionId,
      camera: camera,
      engine: request.engine,
      width: 1920,
      height: 1080,
    );
  }

  @override
  Future<void> stopSession(String sessionId) async {
    stoppedSessions.add(sessionId);
    _onDecode = null;
    _onFailure = null;
  }

  @override
  Future<RawDecode?> decodeImage({
    required Uint8List bytes,
    required String mimeType,
    required ScanMode mode,
    required ScanEngine engine,
  }) async {
    decodeRequests.add((mimeType: mimeType, mode: mode, engine: engine));
    final error = decodeImageError;
    if (error != null) throw error;
    return imageDecode;
  }

  @override
  void registerView({required String viewId, required String containerId}) {
    registeredViewIds.add(viewId);
  }

  @override
  Widget buildPreview(String viewId) => const SizedBox.expand(key: previewKey);
}
