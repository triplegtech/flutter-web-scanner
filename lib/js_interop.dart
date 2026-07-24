@JS()
library js_interop;

import 'dart:js_interop';
import 'package:web/web.dart' as web;

// --- NEW BINDING ---
@JS('getVideoInputDevices')
external JSPromise<JSArray<JSObject>> getVideoInputDevices();

// --- MODIFIED BINDING ---
@JS('startCamera')
external JSPromise<JSAny?> startCamera(
  String videoContainerId,
  String viewId,
  String? deviceId,
  JSFunction onDetect,
  JSFunction onError,
);

@JS('stopCamera')
external JSPromise<JSAny?> stopCamera(String viewId);

@JS('decodeBarcodeFromImage')
external JSPromise<JSObject?> decodeBarcodeFromImage(web.File imageFile);
