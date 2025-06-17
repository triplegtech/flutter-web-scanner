import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:js/js_util.dart' as js_util;
import 'package:omni_qrcode_barcode_web_reader/src/helpers/mimetype_helper.dart';
import '../../js_interop.dart' as interop;

// For web, you'll still need html.File if you directly pass it to JS
// For mobile, you'd get Uint8List from XFile
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html if (dart.library.io) 'dart:io';

import 'package:omni_qrcode_barcode_web_reader/src/models/barcode_result.dart';

Future<BarcodeResult?> decodeBarcodeFromBytes(Uint8List imageData) async {
  if (!kIsWeb) {
    throw UnsupportedError(
        'Barcode decoding from bytes is currently supported only on Web via this package.');
  }

  try {
    final blob = html.Blob([imageData]);
    String inferredType = inferMimeTypeFromBytes(imageData) ?? 'image/unknown';
    final imageFile = html.File(
        [blob],
        'image_from_bytes.${inferredType.split('/').last}',
        {'type': inferredType});

    if (kDebugMode) {
      print(
          "Decoding barcode from bytes. Inferred type: $inferredType, Size: ${imageData.lengthInBytes}");
    }

    final dynamic result = await js_util.promiseToFuture<dynamic>(
      interop.decodeBarcodeFromImage(imageFile),
    );

    if (result != null && result is Map) {
      final String? value = js_util.getProperty(result, 'value');
      final String? format = js_util.getProperty(result, 'format');
      if (value != null && format != null) {
        return BarcodeResult(value: value, format: format);
      } else {
        throw Exception(
            "Failed to decode barcode: Invalid result structure from JS.");
      }
    } else if (result == null) {
      return null;
    } else {
      throw Exception("Error decoding image: ${result.toString()}");
    }
  } catch (e, s) {
    log("Error in decodeBarcodeFromBytes", error: e, stackTrace: s);
    rethrow;
  }
}
