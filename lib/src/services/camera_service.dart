// lib/src/camera_service.dart
// ignore_for_file: avoid_web_libraries_in_flutter, unused_import, avoid_print

import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:js_util' as js_util;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:js/js_util.dart'; // For promiseToFuture and dartify
import 'package:omni_qrcode_barcode_web_reader/src/helpers/language_helper.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_model.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/score_device_model.dart';
import '../../js_interop.dart' as interop;
import 'dart:html' as html;

Future<List<CameraModel>> getCameraDevices() async {
  print("Fetching and prioritizing camera devices (EN/PT)...");
  try {
    final Object jsResult =
        await js_util.promiseToFuture<Object>(interop.getVideoInputDevices());

    if (jsResult is List && jsResult.isNotEmpty) {
      final List<ScoreDeviceModel> scoredDevices = [];

      // --- Define Keywords ---
      const frontKeywords = ['front', 'frontal', 'user', 'usuário', 'selfie'];
      const backKeywords = [
        'back',
        'traseira',
        'rear',
        'environment',
        'ambiente'
      ];
      const wideKeywords = ['wide', 'grande angular', 'angular'];
      const teleKeywords = ['tele', 'teleobjetiva', 'zoom'];
      const otherLensKeywords = [
        'depth',
        'profundidade',
        'fisheye',
        'olho de peixe',
        'macro',
        'tripla'
      ];
      const genericKeywords = ['camera', 'câmera'];

      // 2. Score each device
      for (final item in jsResult) {
        final deviceId = js_util.getProperty<String?>(item, 'deviceId');
        final label = js_util.getProperty<String?>(item, 'label') ?? '';

        if (deviceId != null && deviceId.isNotEmpty) {
          final device = CameraModel(deviceId: deviceId, label: label);
          final lowerCaseLabel = label.toLowerCase();

          int score = 100; // Default high score
          bool isLikelyFront = false;
          bool isLikelyBack = false;
          bool hasSpecialLens = false;
          bool hasGenericName = false;

          // Check for front camera keywords
          for (final keyword in frontKeywords) {
            if (lowerCaseLabel.contains(keyword)) {
              isLikelyFront = true;
              break;
            }
          }

          if (isLikelyFront) {
            score = 999;
          } else {
            for (final keyword in backKeywords) {
              if (lowerCaseLabel.contains(keyword)) {
                isLikelyBack = true;
                score = 10; // Base score for back camera
                break;
              }
            }

            // Check for special lenses (only if it's likely a back camera)
            if (isLikelyBack) {
              for (final keyword in [
                ...wideKeywords,
                ...teleKeywords,
                ...otherLensKeywords
              ]) {
                if (lowerCaseLabel.contains(keyword)) {
                  hasSpecialLens = true;
                  score += 5; // Penalize slightly
                  break; // One special keyword is enough to penalize
                }
              }
            }

            // Check for generic names if no specific back/front keywords found
            if (!isLikelyBack) {
              // Only check if not already identified as back
              for (final keyword in genericKeywords) {
                if (lowerCaseLabel.contains(keyword)) {
                  hasGenericName = true;
                  score = 50; // Less preferred than explicit 'back'
                  break;
                }
              }
              // If label is empty, also treat as generic
              if (lowerCaseLabel.isEmpty) {
                hasGenericName = true;
                score = 55; // Slightly less preferred than "camera"
              }
            }

            // Special case: If it's the ONLY device found, make it highly preferred (override other scores)
            if (jsResult.length == 1 && score < 999) {
              score = 5;
            }
          }

          // Add to list if not explicitly ignored (score < 999)
          if (score < 999) {
            scoredDevices.add(ScoreDeviceModel(device, score));
            print(
                " - Scored Device: ID=${device.deviceId}, Label='${device.label}', Score=$score (Front:$isLikelyFront, Back:$isLikelyBack, Special:$hasSpecialLens, Generic:$hasGenericName)");
          } else {
            print(
                " - Ignoring Device: ID=${device.deviceId}, Label='${device.label}' (Score=$score, likely front)");
          }
        }
      } // End of loop scoring devices

      if (scoredDevices.isEmpty) {
        print(
            "No suitable (non-front) video input devices found after filtering.");
        return [];
      }

      // 3. Sort devices based on score (ascending - lower score first)
      scoredDevices.sort((a, b) => a.score.compareTo(b.score));

      if (GetPlatform.isAndroid) {
        scoredDevices.sort((a, b) => a.device.label
            .toLowerCase()
            .compareTo(b.device.label.toLowerCase()));
      } else if (GetPlatform.isIOS) {
        scoredDevices.retainWhere(
          (sd) =>
              sd.device.label.toLowerCase().contains('ultra wide') ||
              sd.device.label.toLowerCase().contains('ultra-angular') ||
              sd.device.label.toLowerCase().contains('ultra angular'),
        );
      }

      // 4. Extract the sorted CameraModel list
      final List<CameraModel> prioritizedList =
          scoredDevices.map((sd) => sd.device).toList();

      print(
          "Prioritized Camera List (EN/PT) (${prioritizedList.length} devices):");
      prioritizedList
          .forEach((d) => print("  -> ID=${d.deviceId}, Label='${d.label}'"));

      return prioritizedList;
    } else {
      print("Warning: getVideoInputDevices did not return a non-empty List.");
      return [];
    }
  } catch (e) {
    print("Error getting or processing camera devices: $e");
    return []; // Return empty list on error
  }
}
