// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'package:omni_qrcode_barcode_web_reader/src/models/camera_model.dart';

class ScoreDeviceModel {
  final CameraModel device;
  final int score;
  ScoreDeviceModel(
    this.device,
    this.score,
  );
}
