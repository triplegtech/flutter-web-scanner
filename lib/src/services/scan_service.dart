import 'dart:async';
import 'dart:developer';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'package:omni_qrcode_barcode_web_reader/src/helpers/mimetype_helper.dart';
import '../../js_interop.dart' as interop;
import 'package:omni_qrcode_barcode_web_reader/src/models/barcode_result.dart';

Future<BarcodeResult?> decodeBarcodeFromBytes(Uint8List imageData) async {
  if (!kIsWeb) {
    throw UnsupportedError(
        'Barcode decoding from bytes is currently supported only on Web via this package.');
  }

  try {
    String inferredType = inferMimeTypeFromBytes(imageData) ?? 'image/unknown';
    final blob = web.Blob(
      [imageData.toJS].toJS,
      web.BlobPropertyBag(type: inferredType),
    );
    final imageFile = web.File(
      [blob].toJS,
      'image_from_bytes.${inferredType.split('/').last}',
      web.FilePropertyBag(type: inferredType),
    );

    if (kDebugMode) {
      print(
          "Decoding barcode from bytes. Inferred type: $inferredType, Size: ${imageData.lengthInBytes}");
    }

    final JSObject? result =
        await interop.decodeBarcodeFromImage(imageFile).toDart;

    if (result != null) {
      final String? value =
          result.getProperty<JSString?>('value'.toJS)?.toDart;
      if (value != null) {
        return BarcodeResult(value: value, format: 'EAN-13');
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
