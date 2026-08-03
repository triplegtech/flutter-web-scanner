import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_engine.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_mode.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_capabilities.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_model.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/scanner_failure.dart';
import 'package:omni_qrcode_barcode_web_reader/src/platform/scanner_codec.dart';
import 'package:omni_qrcode_barcode_web_reader/src/platform/scanner_interop.dart'
    as interop;
import 'package:omni_qrcode_barcode_web_reader/src/platform/scanner_platform.dart';
import 'package:web/web.dart' as web;

/// Selected on web targets through the conditional import in
/// `scanner_platform.dart`.
ScannerPlatform createScannerPlatform() => WebScannerPlatform();

/// The real browser implementation.
class WebScannerPlatform implements ScannerPlatform {
  /// DOM id of the injected interop script, used to make injection idempotent.
  static const String _scriptId = 'omni-web-scanner-interop-script';

  /// Global the injected script defines.
  static const String _namespace = 'omniScanner';

  static const String _assetPath =
      'packages/omni_qrcode_barcode_web_reader/assets/js/scanner.js';

  /// View ids already registered with the platform view registry.
  ///
  /// Registering the same id twice throws, and a widget that restarts its
  /// camera re-enters [registerView] with the id it already owns.
  final Set<String> _registeredViews = <String>{};

  /// In-flight script injection, so concurrent callers share one fetch instead
  /// of racing to append duplicate `<script>` elements.
  Future<void>? _pendingInjection;

  @override
  Future<EngineAvailability> initialize() async {
    await _ensureScriptInjected();

    if (!globalContext.has(_namespace)) {
      throw const ScannerFailure(
        ScannerFailureKind.engineUnavailable,
        'the interop script was injected but window.omniScanner is missing; '
        'the asset may have failed to parse',
      );
    }

    final availability =
        ScannerCodec.decodeAvailability(interop.probeEnvironment());

    // getUserMedia does not exist outside a secure context, so every later
    // call would fail with a confusing "undefined is not a function".
    if (!availability.secureContext) {
      throw const ScannerFailure(
        ScannerFailureKind.insecureContext,
        'camera access requires HTTPS or localhost',
      );
    }
    return availability;
  }

  @override
  Future<List<CameraModel>> listCameras() async {
    final json = await interop.listCameras().toDart;
    return ScannerCodec.decodeCameras(json.toDart);
  }

  @override
  Future<CameraCapabilities?> probeCamera(String deviceId) async {
    try {
      final json = await interop.probeCamera(deviceId).toDart;
      return ScannerCodec.decodeProbedCapabilities(json.toDart);
    } on Object {
      // Probing is an optimisation, never a requirement. A camera that cannot
      // be opened for measurement simply keeps its label-derived score, and
      // must not prevent scanning with a different one.
      return null;
    }
  }

  @override
  Future<ScanSession> startSession(StartSessionRequest request) async {
    final config = ScannerCodec.encodeStartConfig(
      sessionId: request.sessionId,
      containerId: request.containerId,
      deviceId: request.deviceId,
      mode: request.mode,
      engine: request.engine,
      preferences: request.preferences,
    );

    void handleDecode(String value, String format) {
      request.onDecode(RawDecode(value: value, rawFormat: format));
    }

    void handleFailure(String kind, String message) {
      request.onFailure(ScannerCodec.decodeFailure(kind, message));
    }

    final json = await interop
        .startSession(config, handleDecode.toJS, handleFailure.toJS)
        .toDart;
    return ScannerCodec.decodeSession(json.toDart);
  }

  @override
  Future<void> stopSession(String sessionId) async {
    try {
      await interop.stopSession(sessionId).toDart;
    } on Object {
      // Stopping runs from dispose(), where there is no one left to tell and
      // nothing useful to do. The JS side releases tracks defensively.
    }
  }

  @override
  Future<RawDecode?> decodeImage({
    required Uint8List bytes,
    required String mimeType,
    required ScanMode mode,
    required ScanEngine engine,
  }) async {
    final config = ScannerCodec.encodeDecodeConfig(mode: mode, engine: engine);
    final json = await interop.decodeImage(bytes.toJS, mimeType, config).toDart;
    return ScannerCodec.decodeResult(json.toDart);
  }

  @override
  void registerView({required String viewId, required String containerId}) {
    if (!_registeredViews.add(viewId)) return;

    ui_web.platformViewRegistry.registerViewFactory(viewId, (int _) {
      final container = web.HTMLDivElement()..id = containerId;
      container.style
        ..width = '100%'
        ..height = '100%'
        ..position = 'relative'
        // The video is sized to cover the container; without this a stream
        // wider than the widget paints outside its bounds.
        ..overflow = 'hidden';
      return container;
    });
  }

  @override
  Widget buildPreview(String viewId) => HtmlElementView(viewType: viewId);

  Future<void> _ensureScriptInjected() {
    if (web.document.getElementById(_scriptId) != null) {
      return Future<void>.value();
    }
    return _pendingInjection ??= _injectScript().whenComplete(() {
      _pendingInjection = null;
    });
  }

  /// Loads `scanner.js` from the package asset bundle and evaluates it.
  ///
  /// The script ships as an asset rather than as a tag in the host app's
  /// `index.html` so that consumers cannot end up running a version of the
  /// interop code that disagrees with the Dart bindings. Appending an inline
  /// `<script>` executes it synchronously, so `window.omniScanner` exists by
  /// the time this returns.
  Future<void> _injectScript() async {
    final String code;
    try {
      code = await rootBundle.loadString(_assetPath, cache: false);
    } on Object catch (error) {
      throw ScannerFailure(
        ScannerFailureKind.engineUnavailable,
        'could not load $_assetPath from the asset bundle',
        cause: error,
      );
    }

    final web.Node? host = web.document.head ?? web.document.documentElement;
    if (host == null) {
      throw const ScannerFailure(
        ScannerFailureKind.engineUnavailable,
        'document has neither a head nor a documentElement to attach to',
      );
    }

    final script = web.HTMLScriptElement()
      ..id = _scriptId
      ..type = 'text/javascript'
      ..text = code;
    host.appendChild(script);
  }
}
