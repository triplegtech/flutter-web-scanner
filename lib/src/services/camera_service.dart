// lib/src/camera_service.dart
// ignore_for_file: avoid_web_libraries_in_flutter, unused_import

import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:js_util' as js_util;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:js/js_util.dart'; // For promiseToFuture and dartify
import 'package:omni_qrcode_barcode_web_reader/src/helpers/language_helper.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_model.dart';
import '../../js_interop.dart' as interop;
import 'dart:html' as html;

Future<List<CameraModel>> getCameraDevice() async {
  try {
    final Object jsResult =
        await js_util.promiseToFuture<Object>(interop.getVideoInputDevices());

    if (jsResult is List) {
      final List<CameraModel> devices = [];
      for (final item in jsResult) {
        final deviceId = js_util.getProperty<String?>(item, 'deviceId');
        final label = js_util.getProperty<String?>(item, 'label');

        if (deviceId != null && deviceId.isNotEmpty) {
          devices.add(CameraModel(
            deviceId: deviceId,
            label: (label != null && label.isNotEmpty)
                ? label
                : 'Camera (ID: ${deviceId.substring(0, 8)}...)',
          ));
        }
      }

      log('untreated camera list: $devices');
      
      log('IS ANDROID: ${GetPlatform.isAndroid}');
      log('IS IOS: ${GetPlatform.isIOS}');

      // if (GetPlatform.isIOS) {
      //   if (isDeviceLanguagePortuguese()) {
      //     devices
      //         .retainWhere((d) => d.label.toLowerCase() == 'câmera traseira');
      //   } else {
      //     devices.retainWhere((d) => d.label.toLowerCase() == 'back camera');
      //   }
      // } else if (GetPlatform.isAndroid) {
      //   if (isDeviceLanguagePortuguese()) {
      //     devices
      //         .retainWhere((d) => d.label.toLowerCase().contains('traseira'));
      //   } else {
      //     devices.retainWhere((d) => d.label.toLowerCase().contains('back'));
      //   }

      //   devices.sort(
      //     (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      //   );
      // }

      return devices;
    } else {
      log("Warning: getVideoInputDevices did not return a List.");
      return [];
    }
  } catch (e) {
    log("Error getting camera devices: $e");
    return [];
  }
}
