import 'package:flutter/material.dart';
import 'package:omni_qrcode_barcode_web_reader/src/controllers/scanner_controller.dart';
import 'package:omni_qrcode_barcode_web_reader/src/controllers/scanner_state.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_engine.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/scan_mode.dart';
import 'package:omni_qrcode_barcode_web_reader/src/l10n/scanner_localizations.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/barcode_result.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_preferences.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/scan_rejection.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/scan_validation.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/scanner_failure.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/scanner_overlay_style.dart';
import 'package:omni_qrcode_barcode_web_reader/src/widgets/scanner_error_view.dart';
import 'package:omni_qrcode_barcode_web_reader/src/widgets/scanner_overlay.dart';

/// Builds the widget shown when the scanner fails.
///
/// [retry] is `null` when the failure cannot be recovered by retrying.
typedef ScannerErrorBuilder = Widget Function(
  BuildContext context,
  ScannerFailure failure,
  VoidCallback? retry,
);

/// Live camera scanner for Flutter Web.
///
/// ```dart
/// OmniWebScanner(
///   onDetect: (result) => print('${result.format.name}: ${result.value}'),
///   scanMode: ScanMode.barcode,
/// )
/// ```
///
/// Call `injectOmniWebReaderWebDependencies()` before `runApp` is *not*
/// required in 2.x — the interop script is injected lazily on first use.
class OmniWebScanner extends StatefulWidget {
  const OmniWebScanner({
    super.key,
    required this.onDetect,
    this.onError,
    this.onReject,
    this.scanMode = ScanMode.barcode,
    this.engine = ScanEngine.zxing,
    this.validation,
    this.cameraPreferences,
    this.overlayStyle,
    this.overlayBuilder,
    this.placeholder,
    this.errorBuilder,
    this.showRetryButton = false,
    this.localizations,
    this.width,
    this.height,
    this.controller,
  });

  /// Called once per confirmed, validated detection.
  ///
  /// Unlike 1.x this does not fire on every decoded frame: a result is only
  /// surfaced after it passes [validation] and is confirmed the configured
  /// number of times.
  final ValueChanged<BarcodeResult> onDetect;

  /// Called when the scanner stops with a failure.
  ///
  /// Receives a typed [ScannerFailure] rather than a localised sentence, so
  /// callers can branch on [ScannerFailureKind].
  final ValueChanged<ScannerFailure>? onError;

  /// Called for each decode [validation] discarded, with the rule that
  /// rejected it.
  ///
  /// A scanner that decodes but never emits raises no [ScannerFailure] and
  /// looks exactly like one that is not decoding at all; this is what tells
  /// the two apart. Expect it many times per second while the user is aiming,
  /// so use it to diagnose and leave it null otherwise.
  ///
  /// ```dart
  /// onReject: (r) => debugPrint('$r'),
  /// ```
  final ValueChanged<ScanRejection>? onReject;

  /// What to look for. Also drives the default overlay, the decoder's format
  /// hints, and the default camera and validation tuning.
  final ScanMode scanMode;

  /// Which decoding engine to use. Defaults to [ScanEngine.zxing] so apps
  /// upgrading from 1.x keep their existing `index.html` working.
  ///
  /// Prefer [ScanEngine.auto] for new apps: it uses the browser's native
  /// `BarcodeDetector` where available and falls back to ZXing elsewhere.
  final ScanEngine engine;

  /// Rules a decode must pass before reaching [onDetect]. Defaults to
  /// [ScanValidation.forMode].
  ///
  /// Supplying one *replaces* that preset rather than adding to it. Build on
  /// it instead of around it:
  ///
  /// ```dart
  /// validation: ScanValidation.forMode(ScanMode.barcode).copyWith(minLength: 8)
  /// ```
  ///
  /// Safe to rebuild on every frame, including a [ScanValidation.guard] written
  /// inline: changing this hands the new rules to the live scanner instead of
  /// reopening the camera.
  final ScanValidation? validation;

  /// How the camera is chosen and configured, and how hard the decoder works.
  /// Defaults to [CameraPreferences.forMode].
  ///
  /// Supplying one *replaces* that preset rather than adding to it, so a bare
  /// `CameraPreferences()` in [ScanMode.barcode] silently gives up everything
  /// the mode had tuned: the close-focusing lens ([ScanDistance.near]), the
  /// band-shaped decode region, and — most expensively — the `tryHarder: false`
  /// that keeps ZXing's 1D reader off every row of every frame. On a phone the
  /// difference is a scanner that reads and one that does not. Start from the
  /// preset:
  ///
  /// ```dart
  /// cameraPreferences:
  ///     CameraPreferences.forMode(ScanMode.barcode).copyWith(torch: true)
  /// ```
  final CameraPreferences? cameraPreferences;

  /// Appearance of the built-in overlay. Ignored when [overlayBuilder] is set.
  final ScannerOverlayStyle? overlayStyle;

  /// Replaces the built-in overlay entirely. Return `null` for no overlay.
  final Widget? Function(BuildContext context)? overlayBuilder;

  /// Shown while the camera is starting.
  final Widget? placeholder;

  /// Replaces the built-in error presentation.
  final ScannerErrorBuilder? errorBuilder;

  /// Offer a retry button on recoverable failures.
  final bool showRetryButton;

  /// Copy for the built-in error and loading states.
  ///
  /// Defaults to the bundled translation matching the app's [Locale], falling
  /// back to English.
  final ScannerLocalizations? localizations;

  final double? width;
  final double? height;

  /// An externally owned controller, for callers that need to drive
  /// start/stop or inspect the ranked camera list.
  ///
  /// When provided the caller is responsible for disposing it.
  final ScannerController? controller;

  @override
  State<OmniWebScanner> createState() => _OmniWebScannerState();
}

class _OmniWebScannerState extends State<OmniWebScanner> {
  ScannerController? _internalController;

  ScannerController get _controller =>
      widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = _createController();
    }
    // Starting from a post-frame callback guarantees the platform view's
    // container is in the tree before the interop layer looks for it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.start();
    });
  }

  ScannerController _createController() => ScannerController(
        // Called through `widget` rather than captured, because the controller
        // outlives the build that created it: a callback taken by value here is
        // frozen at that build and goes on reading whatever it closed over then.
        onDetect: (result) => widget.onDetect(result),
        onFailure: (failure) => widget.onError?.call(failure),
        onReject: (rejection) => widget.onReject?.call(rejection),
        mode: widget.scanMode,
        engine: widget.engine,
        validation: widget.validation,
        preferences: widget.cameraPreferences,
      );

  @override
  void didUpdateWidget(covariant OmniWebScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null || oldWidget.controller != null) return;

    // These settings are baked into the session when it starts, so changing
    // one has to rebuild the controller and reopen the camera.
    final needsRestart = widget.scanMode != oldWidget.scanMode ||
        widget.engine != oldWidget.engine ||
        widget.cameraPreferences != oldWidget.cameraPreferences;

    if (needsRestart) {
      _internalController?.dispose();
      _internalController = _createController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.start();
      });
      return;
    }

    // Validation is not one of them: it runs downstream of the decoder, so the
    // live controller can simply be handed the new rules. A guard is a closure,
    // and a closure written inside a build method is a new object every time —
    // including on the rebuild a caller does to show the code they just
    // scanned. Reopening the camera for that blanks the preview after every
    // read.
    if (widget.validation != oldWidget.validation) {
      _internalController?.validation =
          widget.validation ?? ScanValidation.forMode(widget.scanMode);
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  ScannerLocalizations get _localizations =>
      widget.localizations ??
      ScannerLocalizations.forLocale(Localizations.maybeLocaleOf(context));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _buildForState(context, _controller.state),
      ),
    );
  }

  Widget _buildForState(BuildContext context, ScannerState state) {
    // The preview must stay mounted across states: unmounting the platform
    // view would destroy the container the interop layer is waiting on.
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        _controller.buildPreview(),
        switch (state) {
          ScannerReady() => _buildOverlay(context),
          ScannerIdle() || ScannerInitializing() => _buildPlaceholder(context),
          ScannerFailed(:final failure) => _buildError(context, failure),
        },
      ],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final builder = widget.overlayBuilder;
    if (builder != null) {
      return builder(context) ?? const SizedBox.shrink();
    }
    return ScannerOverlay(
      style:
          widget.overlayStyle ?? ScannerOverlayStyle.forMode(widget.scanMode),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final placeholder = widget.placeholder;
    if (placeholder != null) return Center(child: placeholder);

    return Center(
      child: Semantics(
        label: _localizations.initializing,
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, ScannerFailure failure) {
    final retry = widget.showRetryButton && failure.isRetryable
        ? _controller.restart
        : null;

    final builder = widget.errorBuilder;
    if (builder != null) return builder(context, failure, retry);

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: ScannerErrorView(
        failure: failure,
        localizations: _localizations,
        onRetry: retry,
      ),
    );
  }
}
