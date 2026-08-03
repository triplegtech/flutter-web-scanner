import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_qrcode_barcode_web_reader/omni_qrcode_barcode_web_reader.dart';

import '../fakes/fake_scanner_platform.dart';

/// Hand-cranked clock so cooldowns are exercised without real waiting.
class _ManualClock {
  DateTime _now = DateTime.utc(2026, 1, 1);

  DateTime call() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}

void main() {
  late FakeScannerPlatform platform;
  late _ManualClock clock;
  late List<BarcodeResult> detections;
  late List<ScannerFailure> failures;

  setUp(() {
    platform = FakeScannerPlatform();
    clock = _ManualClock();
    detections = <BarcodeResult>[];
    failures = <ScannerFailure>[];
  });

  ScannerController build({
    ScanMode mode = ScanMode.barcode,
    ScanEngine engine = ScanEngine.zxing,
    ScanValidation? validation,
    CameraPreferences? preferences,
  }) {
    return ScannerController(
      onDetect: detections.add,
      onFailure: failures.add,
      mode: mode,
      engine: engine,
      validation: validation,
      preferences: preferences,
      platform: platform,
      clock: clock.call,
      instanceId: 'test',
    );
  }

  CameraModel camera(
    String deviceId,
    String label, {
    int order = 0,
    CameraCapabilities capabilities = CameraCapabilities.unknown,
  }) {
    return CameraModel(
      deviceId: deviceId,
      label: label,
      order: order,
      capabilities: capabilities,
    );
  }

  CameraCapabilities focusing(double minMetres) => CameraCapabilities(
        facing: CameraFacing.back,
        focusDistance: CapabilityRange(min: minMetres, max: 10),
      );

  // A valid EAN-13; its last digit is the correct check digit.
  const validEan = '5901234123457';

  group('construction', () {
    test('registers the platform view backing its preview', () {
      final controller = build();
      addTearDown(controller.dispose);

      expect(platform.registeredViewIds, [controller.viewId]);
      expect(controller.containerId, isNot(controller.viewId));
    });

    test('starts idle', () {
      final controller = build();
      addTearDown(controller.dispose);

      expect(controller.state, isA<ScannerIdle>());
      expect(controller.candidates, isEmpty);
    });

    test('derives defaults from the scan mode', () {
      final controller = build(mode: ScanMode.qrCode);
      addTearDown(controller.dispose);

      // 2D symbols carry error correction, so one read is enough; QR is also
      // read at arm's length, so the near-distance bias must not apply.
      expect(controller.validation.confirmations, 1);
      expect(controller.preferences.distance, ScanDistance.auto);
    });
  });

  group('start', () {
    test('moves to ready and opens the best-ranked camera', () async {
      platform.cameras = [
        camera('front', 'Front Camera', order: 0),
        camera('back', 'Back Camera', order: 1),
      ];
      final controller = build();
      addTearDown(controller.dispose);

      final states = <ScannerState>[];
      controller.addListener(() => states.add(controller.state));

      await controller.start();

      expect(states.map((s) => s.runtimeType), [
        ScannerInitializing,
        ScannerReady,
      ]);
      expect(platform.lastRequestedDeviceId, 'back');
      expect(controller.candidates.first.camera.deviceId, 'back');
    });

    test('passes the resolved engine and container to the platform', () async {
      platform.availability = const EngineAvailability(
        zxingLoaded: true,
        nativeSupported: true,
        secureContext: true,
      );
      final controller = build(engine: ScanEngine.auto);
      addTearDown(controller.dispose);

      await controller.start();

      final request = platform.startRequests.single;
      // `auto` prefers the browser's native detector when it exists.
      expect(request.engine, ScanEngine.native);
      expect(request.containerId, controller.containerId);
      expect(request.sessionId, controller.id);
    });

    test('fails with noCameraFound when the browser reports no devices',
        () async {
      platform.cameras = const <CameraModel>[];
      final controller = build();
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.state, isA<ScannerFailed>());
      expect(failures.single.kind, ScannerFailureKind.noCameraFound);
      expect(platform.startRequests, isEmpty);
    });

    test('fails with engineUnavailable when ZXing was never loaded', () async {
      platform.availability = const EngineAvailability(
        zxingLoaded: false,
        nativeSupported: false,
        secureContext: true,
      );
      final controller = build();
      addTearDown(controller.dispose);

      await controller.start();

      expect(failures.single.kind, ScannerFailureKind.engineUnavailable);
      // Enumerating cameras prompts for permission, which would be a rude
      // thing to do when the scan could never have worked.
      expect(platform.startRequests, isEmpty);
    });

    test('preserves the failure kind reported by the platform', () async {
      platform.startSessionError = const ScannerFailure(
        ScannerFailureKind.cameraInUse,
        'NotReadableError',
      );
      final controller = build();
      addTearDown(controller.dispose);

      await controller.start();

      expect(failures.single.kind, ScannerFailureKind.cameraInUse);
      expect((controller.state as ScannerFailed).isRetryable, isTrue);
    });

    test('normalises an unclassified error instead of letting it escape',
        () async {
      platform.initializeError = StateError('interop blew up');
      final controller = build();
      addTearDown(controller.dispose);

      // FlutterError.reportError would otherwise fail the test; the controller
      // reports the raw error there on purpose, for crash reporters.
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      await controller.start();

      expect(failures.single.kind, ScannerFailureKind.startFailed);
      expect(failures.single.cause, isStateError);
      expect(errors, hasLength(1));
    });

    test('does nothing after dispose', () async {
      final controller = build();
      controller.dispose();

      await controller.start();

      expect(platform.startRequests, isEmpty);
      expect(controller.state, isA<ScannerIdle>());
    });
  });

  group('camera probing', () {
    test('probes the top candidates and re-ranks on what it measured',
        () async {
      // Label-wise the main lens wins at auto distance. Measurement reverses
      // that: it cannot focus on a code held 5 cm away and the ultra-wide can.
      platform.cameras = [
        camera('wide', 'Back Wide Camera', order: 0),
        camera('ultra', 'Back Ultra Wide Camera', order: 1),
      ];
      platform.probeResults = {
        'wide': focusing(0.30),
        'ultra': focusing(0.03),
      };
      final controller = build(mode: ScanMode.qrCode);
      addTearDown(controller.dispose);

      await controller.start();

      expect(platform.probedDeviceIds, containsAll(['wide', 'ultra']));
      expect(platform.lastRequestedDeviceId, 'ultra');
      expect(controller.candidates.first.camera.deviceId, 'ultra');
    });

    test('skips probing when the caller opted out', () async {
      platform.cameras = [camera('back', 'Back Camera')];
      final controller = build(
        preferences: const CameraPreferences(probeCapabilities: false),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(platform.probedDeviceIds, isEmpty);
      expect(controller.state, isA<ScannerReady>());
    });

    test('starts anyway when probing yields nothing', () async {
      platform.cameras = [camera('back', 'Back Camera')];
      platform.probeResults = const <String, CameraCapabilities>{};
      final controller = build();
      addTearDown(controller.dispose);

      await controller.start();

      expect(platform.probedDeviceIds, ['back']);
      expect(controller.state, isA<ScannerReady>());
    });

    test('keeps the label ranking when only some cameras could be measured',
        () async {
      platform.cameras = [
        camera('wide', 'Back Wide Camera', order: 0),
        camera('ultra', 'Back Ultra Wide Camera', order: 1),
      ];
      platform.probeResults = {'wide': focusing(0.03)};
      final controller = build(mode: ScanMode.qrCode);
      addTearDown(controller.dispose);

      await controller.start();

      expect(platform.lastRequestedDeviceId, 'wide');
    });
  });

  group('restart and stop', () {
    test('stop releases the camera and returns to idle', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await controller.start();
      await controller.stop();

      expect(platform.stoppedSessions, [controller.id]);
      expect(platform.hasActiveSession, isFalse);
      expect(controller.state, isA<ScannerIdle>());
    });

    test('restart opens a second session', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await controller.start();
      await controller.restart();

      expect(platform.startRequests, hasLength(2));
      expect(controller.state, isA<ScannerReady>());
    });

    test('a newer start supersedes one already in flight', () async {
      final gate = Completer<void>();
      platform.startSessionGate = gate;
      final controller = build();
      addTearDown(controller.dispose);

      final first = controller.start();
      // Let the first start reach startSession before the second begins.
      await pumpEventQueue();

      platform.startSessionGate = null;
      final second = controller.start();
      gate.complete();
      await Future.wait([first, second]);

      // The superseded session must be closed rather than left holding the
      // camera; leaking it is what made the 1.x scanner fail on the next open.
      expect(platform.stoppedSessions, contains(controller.id));
      expect(controller.state, isA<ScannerReady>());
      expect(platform.startRequests, hasLength(2));
    });

    test('a failure from a superseded start is not reported', () async {
      final gate = Completer<void>();
      platform.startSessionGate = gate;
      platform.startSessionError = const ScannerFailure(
        ScannerFailureKind.cameraInUse,
        'stale',
      );
      final controller = build();
      addTearDown(controller.dispose);

      final first = controller.start();
      await pumpEventQueue();

      platform.startSessionGate = null;
      platform.startSessionError = null;
      final second = controller.start();
      gate.complete();
      await Future.wait([first, second]);

      expect(failures, isEmpty);
      expect(controller.state, isA<ScannerReady>());
    });

    test('dispose stops the session', () async {
      final controller = build();
      await controller.start();

      controller.dispose();
      await pumpEventQueue();

      expect(platform.stoppedSessions, contains(controller.id));
    });
  });

  group('detection pipeline', () {
    test('emits once the read is confirmed, not on the first frame', () async {
      final controller = build();
      addTearDown(controller.dispose);
      await controller.start();

      platform.emitDecode(validEan);
      expect(detections, isEmpty);

      platform.emitDecode(validEan);
      expect(detections.single.value, validEan);
      expect(detections.single.format, BarcodeFormat.ean13);
      expect(detections.single.checksumVerified, isTrue);
    });

    test('keeps the engine-reported format string on the result', () async {
      final controller = build();
      addTearDown(controller.dispose);
      await controller.start();

      platform.emitDecode(validEan, format: 'EAN_13');
      platform.emitDecode(validEan, format: 'EAN_13');

      // The raw string is what a bug report needs; 1.x hardcoded 'EAN-13'
      // regardless of what was actually scanned.
      expect(detections.single.rawFormat, 'EAN_13');
    });

    test('never surfaces a payload that fails its own check digit', () async {
      final controller = build();
      addTearDown(controller.dispose);
      await controller.start();

      for (var i = 0; i < 5; i++) {
        platform.emitDecode('5901234123456');
      }

      expect(detections, isEmpty);
    });

    test('suppresses a code left sitting in frame', () async {
      final controller = build();
      addTearDown(controller.dispose);
      await controller.start();

      for (var i = 0; i < 10; i++) {
        platform.emitDecode(validEan);
      }

      expect(detections, hasLength(1));
    });

    test('reads the same code again once its cooldown has passed', () async {
      final controller = build();
      addTearDown(controller.dispose);
      await controller.start();

      platform.emitDecode(validEan);
      platform.emitDecode(validEan);
      clock.advance(const Duration(seconds: 2));
      platform.emitDecode(validEan);
      platform.emitDecode(validEan);

      expect(detections, hasLength(2));
    });

    test('a restart lets the same code be read immediately', () async {
      final controller = build();
      addTearDown(controller.dispose);
      await controller.start();

      platform.emitDecode(validEan);
      platform.emitDecode(validEan);
      await controller.restart();
      platform.emitDecode(validEan);
      platform.emitDecode(validEan);

      // Without resetting the stabiliser the pre-restart cooldown would swallow
      // the first read after the camera comes back.
      expect(detections, hasLength(2));
    });

    test('honours a caller-supplied guard', () async {
      final controller = build(
        validation: ScanValidation(
          confirmations: 1,
          guard: (value, _) => value.startsWith('59'),
        ),
      );
      addTearDown(controller.dispose);
      await controller.start();

      platform.emitDecode('4006381333931');
      expect(detections, isEmpty);

      platform.emitDecode(validEan);
      expect(detections.single.value, validEan);
    });

    test('reports a session-ending failure raised mid-scan', () async {
      final controller = build();
      addTearDown(controller.dispose);
      await controller.start();

      platform.emitFailure(
        const ScannerFailure(ScannerFailureKind.cameraInUse, 'track ended'),
      );

      expect(failures.single.kind, ScannerFailureKind.cameraInUse);
      expect(controller.state, isA<ScannerFailed>());
    });

    test('ignores decodes that arrive after dispose', () async {
      final controller = build();
      await controller.start();

      // dispose cannot await stopSession, so a frame already in the decoder
      // can still call back after the controller is gone.
      controller.dispose();
      platform.emitDecode(validEan);
      platform.emitDecode(validEan);

      expect(detections, isEmpty);
    });
  });
}
