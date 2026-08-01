import 'package:omni_qrcode_barcode_web_reader/src/enums/camera_facing.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_capabilities.dart';

/// A video input device reported by `navigator.mediaDevices.enumerateDevices`.
class CameraModel {
  const CameraModel({
    required this.deviceId,
    required this.label,
    this.groupId,
    this.order = 0,
    this.capabilities = CameraCapabilities.unknown,
  });

  /// Opaque per-origin identifier used to request this exact camera.
  ///
  /// Empty until the user grants camera permission, which is why selection
  /// cannot rely on it during a first run.
  final String deviceId;

  /// Human-readable label, e.g. `Back Ultra Wide Camera`.
  ///
  /// Also empty pre-permission, and localised to the OS language, so treat it
  /// as a weak hint rather than a key.
  final String label;

  /// Identifies devices belonging to the same physical hardware group.
  final String? groupId;

  /// Position in the browser's enumeration order.
  ///
  /// Used only as a deterministic tie-breaker: browsers tend to list the
  /// default camera first, so a lower value is a marginally better guess when
  /// nothing else separates two candidates.
  final int order;

  /// What the device reports it can do. Starts coarse and is refined once a
  /// live track is available.
  final CameraCapabilities capabilities;

  CameraFacing get facing => capabilities.facing;

  bool get hasLabel => label.trim().isNotEmpty;

  CameraModel copyWith({
    String? deviceId,
    String? label,
    String? groupId,
    int? order,
    CameraCapabilities? capabilities,
  }) {
    return CameraModel(
      deviceId: deviceId ?? this.deviceId,
      label: label ?? this.label,
      groupId: groupId ?? this.groupId,
      order: order ?? this.order,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  /// Returns a copy with [extra] folded into [capabilities].
  CameraModel withCapabilities(CameraCapabilities extra) =>
      copyWith(capabilities: capabilities.mergeWith(extra));

  @override
  bool operator ==(Object other) =>
      other is CameraModel &&
      other.deviceId == deviceId &&
      other.label == label &&
      other.groupId == groupId;

  @override
  int get hashCode => Object.hash(deviceId, label, groupId);

  @override
  String toString() =>
      'CameraModel(deviceId: $deviceId, label: $label, '
      'facing: ${facing.name})';
}
