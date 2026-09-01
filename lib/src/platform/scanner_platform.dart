import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_web_scanner/src/enums/barcode_format.dart';
import 'package:flutter_web_scanner/src/enums/scan_engine.dart';
import 'package:flutter_web_scanner/src/enums/scan_mode.dart';
import 'package:flutter_web_scanner/src/models/camera_capabilities.dart';
import 'package:flutter_web_scanner/src/models/camera_model.dart';
import 'package:flutter_web_scanner/src/models/camera_preferences.dart';
import 'package:flutter_web_scanner/src/models/scanner_failure.dart';
import 'package:flutter_web_scanner/src/platform/scanner_platform_stub.dart'
    if (dart.library.js_interop) 'package:flutter_web_scanner/src/platform/scanner_platform_web.dart'
    as impl;

/// An untrusted decode straight from the engine, before validation.
class RawDecode {
  const RawDecode({required this.value, this.rawFormat});

  final String value;

  /// Engine-reported symbology name, kept verbatim.
  final String? rawFormat;

  BarcodeFormat get format => BarcodeFormat.parse(rawFormat);

  @override
  String toString() => 'RawDecode(value: $value, rawFormat: $rawFormat)';
}

/// Which decoding engines this browser can actually run.
class EngineAvailability {
  const EngineAvailability({
    required this.zxingLoaded,
    required this.nativeSupported,
    required this.secureContext,
    this.nativeFormats = const <String>[],
  });

  /// Whether the ZXing UMD bundle is present on `window`.
  final bool zxingLoaded;

  /// Whether the browser implements the `BarcodeDetector` API.
  final bool nativeSupported;

  /// Whether the page is in a secure context, without which `getUserMedia`
  /// does not exist at all.
  final bool secureContext;

  /// Formats the native detector reports it can decode.
  final List<String> nativeFormats;

  /// Resolves [requested] against what is actually available.
  ///
  /// Throws [ScannerFailure] when the request cannot be satisfied, so the
  /// caller fails at startup with an actionable message rather than silently
  /// scanning with an engine it did not ask for.
  ScanEngine resolve(ScanEngine requested) {
    return switch (requested) {
      ScanEngine.native when nativeSupported => ScanEngine.native,
      ScanEngine.native => throw const ScannerFailure(
        ScannerFailureKind.engineUnavailable,
        'BarcodeDetector is not implemented in this browser; use '
        'ScanEngine.auto or ScanEngine.zxing',
      ),
      ScanEngine.auto when nativeSupported => ScanEngine.native,
      ScanEngine.auto when zxingLoaded => ScanEngine.zxing,
      ScanEngine.auto => throw const ScannerFailure(
        ScannerFailureKind.engineUnavailable,
        'Neither BarcodeDetector nor the ZXing bundle is available; add the '
        'ZXing script tag to web/index.html',
      ),
      ScanEngine.zxing when zxingLoaded => ScanEngine.zxing,
      ScanEngine.zxing => throw const ScannerFailure(
        ScannerFailureKind.engineUnavailable,
        'The ZXing library was not found on window; add its script tag to '
        'web/index.html',
      ),
    };
  }
}

/// A running camera + decoder pair.
class ScanSession {
  const ScanSession({
    required this.id,
    required this.camera,
    required this.engine,
    this.width,
    this.height,
  });

  final String id;

  /// The camera actually opened, with capabilities refined from the live
  /// track. May differ from the requested one when constraint fallback kicked
  /// in.
  final CameraModel camera;

  /// The engine actually in use after [EngineAvailability.resolve].
  final ScanEngine engine;

  /// Negotiated frame size, which can be lower than requested.
  final int? width;
  final int? height;

  @override
  String toString() =>
      'ScanSession(id: $id, camera: ${camera.label}, '
      'engine: ${engine.name}, size: ${width}x$height)';
}

/// Everything needed to start scanning.
class StartSessionRequest {
  const StartSessionRequest({
    required this.sessionId,
    required this.containerId,
    required this.mode,
    required this.engine,
    required this.preferences,
    required this.onDecode,
    required this.onFailure,
    this.deviceId,
  });

  /// Unique per widget instance; also the key used to stop the session.
  final String sessionId;

  /// DOM id of the element the video should be mounted into.
  final String containerId;

  final String? deviceId;
  final ScanMode mode;
  final ScanEngine engine;
  final CameraPreferences preferences;

  /// Called for every raw decode, many times per second. Validation happens
  /// downstream in [DetectionStabilizer].
  final void Function(RawDecode decode) onDecode;

  /// Called only for failures that end the session. Transient decode errors
  /// are never reported here.
  final void Function(ScannerFailure failure) onFailure;
}

/// The browser-facing surface of the scanner.
///
/// Everything that touches `dart:js_interop`, `package:web` or `dart:ui_web`
/// lives behind this interface, for two reasons:
///
/// * Those libraries do not compile on the Dart VM, so without this seam
///   `flutter test` cannot even load the package, let alone test a widget.
/// * It makes the browser a swappable collaborator, so failure paths that are
///   impossible to trigger on real hardware — a camera in use, an
///   overconstrained device, a missing engine — become ordinary test cases.
abstract interface class ScannerPlatform {
  /// Injects the interop script and reports what the browser supports.
  ///
  /// Idempotent; safe to call before every session.
  Future<EngineAvailability> initialize();

  /// Enumerates video inputs, requesting permission first so labels and device
  /// ids are populated.
  Future<List<CameraModel>> listCameras();

  /// Opens [deviceId] briefly to read its live capabilities, then closes it.
  ///
  /// Returns `null` when the camera could not be opened; probing is best-effort
  /// and must never block scanning.
  Future<CameraCapabilities?> probeCamera(String deviceId);

  /// Starts a camera and begins decoding into [StartSessionRequest.onDecode].
  Future<ScanSession> startSession(StartSessionRequest request);

  /// Stops the session and releases its camera tracks.
  Future<void> stopSession(String sessionId);

  /// Decodes a still image.
  Future<RawDecode?> decodeImage({
    required Uint8List bytes,
    required String mimeType,
    required ScanMode mode,
    required ScanEngine engine,
  });

  /// Registers the platform view backing [viewId].
  void registerView({required String viewId, required String containerId});

  /// The widget that hosts the video element.
  Widget buildPreview(String viewId);
}

/// Resolves the [ScannerPlatform] implementation for the current target.
///
/// Web builds get the real implementation through a conditional import; every
/// other target, including the VM used by `flutter test`, gets a stub that
/// fails with [ScannerFailureKind.unsupportedPlatform].
abstract final class ScannerPlatformResolver {
  static ScannerPlatform? _override;
  static ScannerPlatform? _cached;

  static ScannerPlatform get instance =>
      _override ?? (_cached ??= impl.createScannerPlatform());

  /// Substitutes a fake implementation. Tests must call [reset] afterwards.
  @visibleForTesting
  static set instance(ScannerPlatform platform) => _override = platform;

  /// Restores the real implementation.
  @visibleForTesting
  static void reset() => _override = null;
}
