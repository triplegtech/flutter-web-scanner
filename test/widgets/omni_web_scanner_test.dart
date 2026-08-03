import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_qrcode_barcode_web_reader/omni_qrcode_barcode_web_reader.dart';

import '../fakes/fake_scanner_platform.dart';

void main() {
  late FakeScannerPlatform platform;
  late List<BarcodeResult> detections;
  late List<ScannerFailure> failures;

  setUp(() {
    platform = FakeScannerPlatform();
    detections = <BarcodeResult>[];
    failures = <ScannerFailure>[];
    // The widget builds its own controller, which resolves the platform from
    // here; on the VM the real one would fail with unsupportedPlatform.
    ScannerPlatformResolver.instance = platform;
  });

  tearDown(ScannerPlatformResolver.reset);

  // A valid EAN-13.
  const validEan = '5901234123457';

  Widget host(
    Widget scanner, {
    Locale? locale,
  }) {
    // The locale is overridden below the app rather than on it: the bundled
    // Material delegates only cover English, and declaring an unsupported app
    // locale makes the framework log a warning that fails the test.
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: locale == null
                ? scanner
                : Builder(
                    builder: (context) => Localizations.override(
                      context: context,
                      locale: locale,
                      child: scanner,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// Pumps until the start sequence has settled.
  ///
  /// `pumpAndSettle` is unusable here: the overlay's scan line animates
  /// forever, so it would time out rather than settle.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  group('lifecycle', () {
    testWidgets('shows the placeholder before the camera is live',
        (tester) async {
      await tester.pumpWidget(host(OmniWebScanner(onDetect: detections.add)));

      // First frame only: start() runs from a post-frame callback.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ScannerOverlay), findsNothing);

      await settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ScannerOverlay), findsOneWidget);
    });

    testWidgets('keeps the preview mounted across every state', (tester) async {
      platform.startSessionError = const ScannerFailure(
        ScannerFailureKind.cameraInUse,
        'NotReadableError',
      );
      await tester.pumpWidget(host(OmniWebScanner(onDetect: detections.add)));

      // Unmounting the platform view would destroy the container the interop
      // layer is waiting on, so it has to survive loading and failure alike.
      expect(find.byKey(FakeScannerPlatform.previewKey), findsOneWidget);
      await settle(tester);
      expect(find.byKey(FakeScannerPlatform.previewKey), findsOneWidget);
    });

    testWidgets('uses a caller-supplied placeholder', (tester) async {
      await tester.pumpWidget(
        host(
          OmniWebScanner(
            onDetect: detections.add,
            placeholder: const Text('Aponte para o código'),
          ),
        ),
      );

      expect(find.text('Aponte para o código'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('releases the camera when it leaves the tree', (tester) async {
      await tester.pumpWidget(host(OmniWebScanner(onDetect: detections.add)));
      await settle(tester);

      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pump();

      expect(platform.stoppedSessions, isNotEmpty);
    });

    testWidgets('does not dispose a controller it does not own',
        (tester) async {
      final controller = ScannerController(
        onDetect: detections.add,
        platform: platform,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(OmniWebScanner(
        onDetect: detections.add,
        controller: controller,
      )));
      await settle(tester);
      expect(controller.state, isA<ScannerReady>());

      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pump();

      // Ownership stays with the caller: unmounting must not tear down a
      // controller they may still be driving.
      expect(platform.stoppedSessions, isEmpty);
      expect(controller.state, isA<ScannerReady>());
    });
  });

  group('reconfiguration', () {
    testWidgets('reopens the camera when the scan mode changes',
        (tester) async {
      await tester.pumpWidget(host(OmniWebScanner(onDetect: detections.add)));
      await settle(tester);

      await tester.pumpWidget(
        host(OmniWebScanner(
          onDetect: detections.add,
          scanMode: ScanMode.qrCode,
        )),
      );
      await settle(tester);

      expect(platform.startRequests, hasLength(2));
      expect(platform.startRequests.last.mode, ScanMode.qrCode);
    });

    testWidgets('does not reopen the camera for a cosmetic change',
        (tester) async {
      await tester.pumpWidget(host(OmniWebScanner(onDetect: detections.add)));
      await settle(tester);

      await tester.pumpWidget(
        host(OmniWebScanner(
          onDetect: detections.add,
          overlayStyle: const ScannerOverlayStyle(),
        )),
      );
      await settle(tester);

      // Restarting the stream for an overlay tweak would blank the preview for
      // several hundred milliseconds.
      expect(platform.startRequests, hasLength(1));
    });
  });

  group('detections', () {
    testWidgets('forwards a confirmed read to onDetect', (tester) async {
      await tester.pumpWidget(host(OmniWebScanner(onDetect: detections.add)));
      await settle(tester);

      platform.emitDecode(validEan);
      expect(detections, isEmpty);
      platform.emitDecode(validEan);

      expect(detections.single.value, validEan);
    });

    testWidgets('emits on the first read in QR mode', (tester) async {
      await tester.pumpWidget(
        host(OmniWebScanner(
          onDetect: detections.add,
          scanMode: ScanMode.qrCode,
        )),
      );
      await settle(tester);

      platform.emitDecode('https://example.com', format: 'QR_CODE');

      expect(detections.single.format, BarcodeFormat.qrCode);
    });
  });

  group('failures', () {
    testWidgets('reports the failure and shows the built-in error view',
        (tester) async {
      platform.availability = const EngineAvailability(
        zxingLoaded: false,
        nativeSupported: false,
        secureContext: true,
      );
      await tester.pumpWidget(
        host(OmniWebScanner(onDetect: detections.add, onError: failures.add)),
      );
      await settle(tester);

      expect(failures.single.kind, ScannerFailureKind.engineUnavailable);
      expect(
          find.text(ScannerLocalizations.en.engineUnavailable), findsOneWidget);
    });

    testWidgets('hides the retry button unless the caller asks for it',
        (tester) async {
      platform.startSessionError = const ScannerFailure(
        ScannerFailureKind.cameraInUse,
        'NotReadableError',
      );
      await tester.pumpWidget(host(OmniWebScanner(onDetect: detections.add)));
      await settle(tester);

      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('retry reopens the camera', (tester) async {
      platform.startSessionError = const ScannerFailure(
        ScannerFailureKind.cameraInUse,
        'NotReadableError',
      );
      await tester.pumpWidget(
        host(OmniWebScanner(onDetect: detections.add, showRetryButton: true)),
      );
      await settle(tester);

      expect(find.text(ScannerLocalizations.en.retry), findsOneWidget);

      platform.startSessionError = null;
      await tester.tap(find.byType(ElevatedButton));
      await settle(tester);

      expect(platform.startRequests, hasLength(2));
      expect(find.byType(ScannerOverlay), findsOneWidget);
    });

    testWidgets('offers no retry for a failure that would repeat',
        (tester) async {
      platform.startSessionError = const ScannerFailure(
        ScannerFailureKind.permissionDenied,
        'NotAllowedError',
      );
      await tester.pumpWidget(
        host(OmniWebScanner(onDetect: detections.add, showRetryButton: true)),
      );
      await settle(tester);

      // Retrying a denied permission fails identically and reads as a broken
      // button.
      expect(find.byType(ElevatedButton), findsNothing);
      expect(
        find.text(ScannerLocalizations.en.permissionDenied),
        findsOneWidget,
      );
    });

    testWidgets('errorBuilder replaces the built-in error view',
        (tester) async {
      platform.startSessionError = const ScannerFailure(
        ScannerFailureKind.permissionDenied,
        'NotAllowedError',
      );
      ScannerFailure? seen;
      var retryOffered = true;

      await tester.pumpWidget(
        host(OmniWebScanner(
          onDetect: detections.add,
          showRetryButton: true,
          errorBuilder: (context, failure, retry) {
            seen = failure;
            retryOffered = retry != null;
            return Text('erro: ${failure.kind.name}');
          },
        )),
      );
      await settle(tester);

      expect(find.text('erro: permissionDenied'), findsOneWidget);
      expect(seen?.message, 'NotAllowedError');
      // The builder is handed a null retry rather than being left to work out
      // which kinds are worth retrying.
      expect(retryOffered, isFalse);
    });
  });

  group('overlay', () {
    testWidgets('overlayBuilder replaces the default overlay', (tester) async {
      await tester.pumpWidget(
        host(OmniWebScanner(
          onDetect: detections.add,
          overlayBuilder: (context) => const Text('mira'),
        )),
      );
      await settle(tester);

      expect(find.text('mira'), findsOneWidget);
      expect(find.byType(ScannerOverlay), findsNothing);
    });

    testWidgets('a null overlayBuilder result renders no overlay',
        (tester) async {
      await tester.pumpWidget(
        host(OmniWebScanner(
          onDetect: detections.add,
          overlayBuilder: (context) => null,
        )),
      );
      await settle(tester);

      expect(find.byType(ScannerOverlay), findsNothing);
      expect(find.byKey(FakeScannerPlatform.previewKey), findsOneWidget);
    });
  });

  group('localization', () {
    testWidgets('follows the app locale', (tester) async {
      platform.startSessionError = const ScannerFailure(
        ScannerFailureKind.permissionDenied,
        'NotAllowedError',
      );
      await tester.pumpWidget(
        host(
          OmniWebScanner(onDetect: detections.add),
          locale: const Locale('pt', 'BR'),
        ),
      );
      await settle(tester);

      expect(
        find.text(ScannerLocalizations.ptBr.permissionDenied),
        findsOneWidget,
      );
    });

    testWidgets('falls back to English for an unbundled language',
        (tester) async {
      platform.startSessionError = const ScannerFailure(
        ScannerFailureKind.permissionDenied,
        'NotAllowedError',
      );
      await tester.pumpWidget(
        host(
          OmniWebScanner(onDetect: detections.add),
          locale: const Locale('en'),
        ),
      );
      await settle(tester);

      expect(
        find.text(ScannerLocalizations.en.permissionDenied),
        findsOneWidget,
      );
    });

    testWidgets('caller-supplied copy wins over the app locale',
        (tester) async {
      platform.startSessionError = const ScannerFailure(
        ScannerFailureKind.permissionDenied,
        'NotAllowedError',
      );
      await tester.pumpWidget(
        host(
          OmniWebScanner(
            onDetect: detections.add,
            localizations: ScannerLocalizations.es,
          ),
          locale: const Locale('pt', 'BR'),
        ),
      );
      await settle(tester);

      expect(
        find.text(ScannerLocalizations.es.permissionDenied),
        findsOneWidget,
      );
    });
  });
}
