@JS()
library js_interop;

import 'package:js/js.dart';
import 'dart:html' as html;

// --- NEW BINDING ---
@JS('getVideoInputDevices')
external Future<dynamic> getVideoInputDevices();

// --- MODIFIED BINDING ---
@JS('startCamera')
external Future<void> startCamera(
  String videoContainerId,
  String viewId,
  String? deviceId,
  @JS('Function') void Function(String value, String format) onDetect,
  @JS('Function') void Function(String error) onError,
);

@JS('stopCamera')
external Future<void> stopCamera(String viewId);

@JS('decodeBarcodeFromImage')
external Future<dynamic> decodeBarcodeFromImage(html.File imageFile);