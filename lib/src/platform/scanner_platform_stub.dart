import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_engine.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_mode.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_capabilities.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_model.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/scanner_failure.dart';
import 'package:omni_qrcode_barcode_web_reader/src/platform/scanner_platform.dart';

/// Selected on every non-web target through the conditional import in
/// `scanner_platform.dart`.
ScannerPlatform createScannerPlatform() => const UnsupportedScannerPlatform();

/// Fails every operation with [ScannerFailureKind.unsupportedPlatform].
///
/// This exists so the package remains *compilable* off the web — which is what
/// lets `flutter test` run on the VM — while still refusing to pretend it can
/// scan. It is never the platform under test: widget tests inject a fake.
class UnsupportedScannerPlatform implements ScannerPlatform {
  const UnsupportedScannerPlatform();

  static const ScannerFailure _failure = ScannerFailure(
    ScannerFailureKind.unsupportedPlatform,
    'omni_qrcode_barcode_web_reader only supports Flutter Web',
  );

  @override
  Future<EngineAvailability> initialize() async => throw _failure;

  @override
  Future<List<CameraModel>> listCameras() async => throw _failure;

  @override
  Future<CameraCapabilities?> probeCamera(String deviceId) async => null;

  @override
  Future<ScanSession> startSession(StartSessionRequest request) async =>
      throw _failure;

  @override
  Future<void> stopSession(String sessionId) async {}

  @override
  Future<RawDecode?> decodeImage({
    required Uint8List bytes,
    required String mimeType,
    required ScanMode mode,
    required ScanEngine engine,
  }) async =>
      throw _failure;

  @override
  void registerView({required String viewId, required String containerId}) {}

  @override
  Widget buildPreview(String viewId) => const SizedBox.expand();
}
