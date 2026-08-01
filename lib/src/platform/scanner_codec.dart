import 'dart:convert';

import 'package:omni_qrcode_barcode_web_reader/src/enums/camera_facing.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_engine.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_mode.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_capabilities.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_model.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_preferences.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/capability_range.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/scanner_failure.dart';
import 'package:omni_qrcode_barcode_web_reader/src/platform/scanner_platform.dart';

/// Translates between Dart models and the JSON the interop layer exchanges.
///
/// Two decisions shape this file.
///
/// **JSON instead of structured `JSObject`s.** Walking nested JS objects
/// through `getProperty` is verbose, easy to get subtly wrong, and — the
/// deciding factor — impossible to exercise off the browser. With JSON, every
/// field mapping is a pure function that VM tests can drive with fixtures,
/// including the malformed shapes real browsers actually emit.
///
/// **A result envelope instead of promise rejection.** Every JS call resolves
/// with `{ok: true, data}` or `{ok: false, kind, message}` and never rejects.
/// A rejected promise surfaces in Dart as an opaque `JSObject` whose shape
/// varies by browser, which is how 1.x ended up stringifying DOM exceptions
/// into user-facing text. The envelope makes the failure taxonomy explicit and
/// decodable.
abstract final class ScannerCodec {
  /// Unwraps a result envelope.
  ///
  /// Throws [ScannerFailure] when the JS side reported a failure, so callers
  /// can use ordinary `try`/`catch` instead of inspecting return values.
  static Object? unwrap(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error) {
      throw ScannerFailure(
        ScannerFailureKind.unknown,
        'interop layer returned malformed JSON: $json',
        cause: error,
      );
    }

    final map = _asMap(decoded);
    if (map['ok'] == true) return map['data'];

    throw decodeFailure(
      map['kind'] as String? ?? ScannerFailureKind.unknown.name,
      map['message'] as String? ?? 'interop call failed without a message',
    );
  }

  /// Parses the environment probe result.
  static EngineAvailability decodeAvailability(String json) {
    final map = _asMap(unwrap(json));
    return EngineAvailability(
      zxingLoaded: map['zxingLoaded'] == true,
      nativeSupported: map['nativeSupported'] == true,
      secureContext: map['secureContext'] == true,
      nativeFormats: _asStringList(map['nativeFormats']),
    );
  }

  /// Parses the camera list, discarding entries without a usable identity.
  static List<CameraModel> decodeCameras(String json) {
    final raw = unwrap(json);
    if (raw is! List) return const <CameraModel>[];

    final cameras = <CameraModel>[];
    for (var index = 0; index < raw.length; index++) {
      final entry = raw[index];
      if (entry is! Map) continue;
      // A video input with no deviceId cannot be requested by id later, and
      // every browser that grants permission provides one.
      final deviceId = entry['deviceId'];
      if (deviceId is! String) continue;
      cameras.add(
        CameraModel(
          deviceId: deviceId,
          label: entry['label'] is String ? entry['label'] as String : '',
          groupId:
              entry['groupId'] is String ? entry['groupId'] as String : null,
          order: index,
          capabilities: decodeCapabilities(entry['capabilities']) ??
              CameraCapabilities.unknown,
        ),
      );
    }
    return cameras;
  }

  /// Parses a capability probe envelope.
  static CameraCapabilities? decodeProbedCapabilities(String json) =>
      decodeCapabilities(unwrap(json));

  /// Parses a raw `getCapabilities()` payload.
  ///
  /// Returns `null` when the browser reported nothing, which is the common
  /// case on Safari and Firefox.
  static CameraCapabilities? decodeCapabilities(Object? raw) {
    if (raw is! Map) return null;
    return CameraCapabilities(
      facing: CameraFacing.fromConstraint(_firstString(raw['facingMode'])),
      focusDistance: CapabilityRange.tryParse(raw['focusDistance']),
      zoom: CapabilityRange.tryParse(raw['zoom']),
      maxWidth: _maxOf(raw['width']),
      maxHeight: _maxOf(raw['height']),
      focusModes: _asStringList(raw['focusMode']),
      supportsTorch: _reportsTorch(raw['torch']),
    );
  }

  /// Parses the result of starting a session.
  static ScanSession decodeSession(String json) {
    final map = _asMap(unwrap(json));
    return ScanSession(
      id: map['sessionId'] as String? ?? '',
      camera: CameraModel(
        deviceId: map['deviceId'] as String? ?? '',
        label: map['label'] as String? ?? '',
        groupId: map['groupId'] as String?,
        capabilities: decodeCapabilities(map['capabilities']) ??
            CameraCapabilities.unknown,
      ),
      engine: decodeEngine(map['engine']),
      width: (map['width'] as num?)?.round(),
      height: (map['height'] as num?)?.round(),
    );
  }

  /// Parses a single decode result, or `null` when nothing was found.
  static RawDecode? decodeResult(String json) {
    final raw = unwrap(json);
    if (raw is! Map) return null;
    final value = raw['value'];
    if (value is! String || value.isEmpty) return null;
    return RawDecode(
      value: value,
      rawFormat: raw['format'] is String ? raw['format'] as String : null,
    );
  }

  /// Maps a failure reported by the JS layer back to a typed failure.
  ///
  /// [kind] is either one of our own [ScannerFailureKind] names or, when the
  /// JS side forwarded a `DOMException` verbatim, its `name`.
  static ScannerFailure decodeFailure(String kind, String message) {
    final parsed = _firstWhereOrNull(
      ScannerFailureKind.values,
      (candidate) => candidate.name == kind,
    );
    return ScannerFailure(
      parsed ?? ScannerFailure.kindFromDomError(kind),
      message,
    );
  }

  static ScanEngine decodeEngine(Object? raw) =>
      _firstWhereOrNull(ScanEngine.values, (engine) => engine.name == raw) ??
      ScanEngine.zxing;

  /// Builds the config handed to `startSession`.
  static String encodeStartConfig({
    required String sessionId,
    required String containerId,
    required String? deviceId,
    required ScanMode mode,
    required ScanEngine engine,
    required CameraPreferences preferences,
  }) {
    return jsonEncode(<String, Object?>{
      'sessionId': sessionId,
      'containerId': containerId,
      'deviceId': deviceId,
      'engine': engine.name,
      'formats': encodeFormats(mode, engine),
      'idealWidth': preferences.idealWidth,
      'idealHeight': preferences.idealHeight,
      'idealFrameRate': preferences.idealFrameRate,
      'continuousFocus': preferences.continuousFocus,
      'zoom': preferences.zoom,
      'torch': preferences.torch,
    });
  }

  /// Builds the config handed to `decodeImage`.
  static String encodeDecodeConfig({
    required ScanMode mode,
    required ScanEngine engine,
  }) {
    return jsonEncode(<String, Object?>{
      'engine': engine.name,
      'formats': encodeFormats(mode, engine),
    });
  }

  /// Format hints in the wire spelling the target engine expects.
  ///
  /// Formats the engine has no name for are dropped rather than passed
  /// through: `BarcodeDetector` throws on an unknown format string, which
  /// would turn a harmless hint into a hard startup failure.
  static List<String> encodeFormats(ScanMode mode, ScanEngine engine) {
    final names = <String>[];
    for (final format in mode.formats) {
      final name = engine == ScanEngine.native ? format.native : format.zxing;
      if (name != null) names.add(name);
    }
    return names;
  }

  static Map<String, Object?> _asMap(Object? raw) =>
      raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};

  static List<String> _asStringList(Object? raw) => switch (raw) {
        final List list => list.whereType<String>().toList(),
        final String single => <String>[single],
        _ => const <String>[],
      };

  /// Reads the first entry of a capability browsers report as a list.
  ///
  /// `facingMode` is specified as a sequence but some browsers hand back a
  /// bare string, so both shapes are accepted.
  static String? _firstString(Object? raw) => switch (raw) {
        final String single => single,
        final List list =>
          _firstWhereOrNull<Object?>(list, (item) => item is String) as String?,
        _ => null,
      };

  /// `torch` is reported as `true`, or as a list of supported values that
  /// includes `true`, depending on the browser.
  static bool _reportsTorch(Object? raw) => switch (raw) {
        true => true,
        final List list => list.contains(true),
        _ => false,
      };

  /// Extracts the maximum of a `MediaSettingsRange`, or the value itself when
  /// the browser reported a plain number.
  static int? _maxOf(Object? raw) => CapabilityRange.tryParse(raw)?.max.round();

  /// Local stand-in for `package:collection`'s `firstWhereOrNull`, so the
  /// package keeps a minimal dependency set.
  static T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }
}
