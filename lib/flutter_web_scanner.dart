/// Camera-based QR code and barcode scanning for Flutter Web.
///
/// The entry points are [WebScanner] for live scanning and
/// [decodeBarcodeFromBytes] for still images.
///
/// The browser interop script is injected lazily on first use, so unlike 1.x
/// there is no setup call to make before `runApp`. The host app still needs the
/// ZXing script tag in `web/index.html` unless it opts into
/// [ScanEngine.native].
library;

export 'src/controllers/scanner_controller.dart' show ScannerController;
export 'src/controllers/scanner_state.dart'
    show
        ScannerFailed,
        ScannerIdle,
        ScannerInitializing,
        ScannerReady,
        ScannerState;
export 'src/core/barcode_validator.dart'
    show
        BarcodeRejection,
        BarcodeValidator,
        ValidationAccepted,
        ValidationOutcome,
        ValidationRejected;
export 'src/core/camera_selector.dart' show CameraCandidate, CameraSelector;
export 'src/enums/barcode_format.dart' show BarcodeFormat;
export 'src/enums/camera_facing.dart' show CameraFacing;
export 'src/enums/lens_kind.dart' show LensKind;
export 'src/enums/scan_distance.dart' show ScanDistance;
export 'src/enums/scan_engine.dart' show ScanEngine;
export 'src/enums/scan_mode.dart' show ScanMode;
export 'src/l10n/scanner_localizations.dart' show ScannerLocalizations;
export 'src/models/barcode_result.dart' show BarcodeResult;
export 'src/models/camera_capabilities.dart' show CameraCapabilities;
export 'src/models/camera_model.dart' show CameraModel;
export 'src/models/camera_preferences.dart' show CameraPreferences;
export 'src/models/capability_range.dart' show CapabilityRange;
export 'src/models/scan_rejection.dart' show ScanRejection;
export 'src/models/scan_validation.dart' show BarcodeGuard, ScanValidation;
export 'src/models/scanner_failure.dart'
    show ScannerFailure, ScannerFailureKind;
export 'src/models/scanner_overlay_style.dart' show ScannerOverlayStyle;
export 'src/platform/scanner_platform.dart'
    show
        EngineAvailability,
        RawDecode,
        ScanSession,
        ScannerPlatform,
        ScannerPlatformResolver,
        StartSessionRequest;
export 'src/services/scan_service.dart' show decodeBarcodeFromBytes;
export 'src/widgets/web_scanner.dart' show WebScanner, ScannerErrorBuilder;
export 'src/widgets/scanner_overlay.dart' show ScannerOverlay;
