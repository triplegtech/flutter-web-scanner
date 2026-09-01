/// Bindings to the `window.flutterWebScanner` namespace defined by
/// `assets/js/scanner.js`.
///
/// Every call exchanges JSON strings rather than structured objects. That keeps
/// this file to a flat list of primitives — the part of interop that is hardest
/// to get wrong — and pushes all field mapping into `ScannerCodec`, where it is
/// testable without a browser.
///
/// Adding a function here requires a matching entry inside the `flutterWebScanner`
/// object in `assets/js/scanner.js`.
@JS()
library;

import 'dart:js_interop';

/// Reports which engines and browser features are available.
///
/// Synchronous because it only inspects `window`.
@JS('flutterWebScanner.probeEnvironment')
external String probeEnvironment();

/// Requests camera permission, then enumerates video inputs.
///
/// Resolves to a JSON array of camera descriptors.
@JS('flutterWebScanner.listCameras')
external JSPromise<JSString> listCameras();

/// Opens a camera briefly to read its live capabilities.
///
/// Resolves to a JSON capability object, or the string `null`.
@JS('flutterWebScanner.probeCamera')
external JSPromise<JSString> probeCamera(String deviceId);

/// Starts a camera and begins decoding.
///
/// [onDecode] is invoked as `(value, format)` for every raw decode.
/// [onFailure] is invoked as `(kind, message)` only for session-ending errors.
@JS('flutterWebScanner.startSession')
external JSPromise<JSString> startSession(
  String configJson,
  JSFunction onDecode,
  JSFunction onFailure,
);

/// Stops a session and releases its tracks. Safe to call for unknown ids.
@JS('flutterWebScanner.stopSession')
external JSPromise<JSAny?> stopSession(String sessionId);

/// Decodes a still image from raw bytes.
///
/// Resolves to a JSON result object, or the string `null` when no code was
/// found.
@JS('flutterWebScanner.decodeImage')
external JSPromise<JSString> decodeImage(
  JSUint8Array bytes,
  String mimeType,
  String configJson,
);
