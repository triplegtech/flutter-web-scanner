// ignore_for_file: public_member_api_docs, sort_constructors_first
class CameraModel {
  final String deviceId;
  final String label;
  CameraModel({
    required this.deviceId,
    required this.label,
  });

  @override
  bool operator ==(covariant CameraModel other) {
    if (identical(this, other)) return true;

    return other.deviceId == deviceId && other.label == label;
  }

  @override
  int get hashCode => deviceId.hashCode ^ label.hashCode;

  @override
  String toString() => 'CameraModel(deviceId: $deviceId, label: $label)';
}
